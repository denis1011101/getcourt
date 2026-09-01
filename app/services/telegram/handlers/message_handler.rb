module Telegram
  module Handlers
    class MessageHandler
      def self.handle(message)
        message = message.to_h if message.respond_to?(:to_h)
        chat_id = message.dig("chat", "id") || message.dig("from", "id")
        return true unless chat_id

        locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
        t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

        return true if Telegram::Flows::Games::InviteFlow.handle_message(message) rescue false

        if Rails.cache.read("telegram:edit:chat:#{chat_id}")
          Telegram::Flows::Games::EditResponder.handle_message(message) rescue nil
          return
        end

        text = message["text"].to_s
        if text.start_with?("/")
          case text.split.first
          when /\A\/chat(@|$)/
            user = Telegram::Helpers::UserLookup.find_user(chat_id)
            if user
              Telegram::Chat::Flow.start(chat_id, user)
            else
              Api.send_simple(chat_id, t.(:user_not_found))
            end
            return
          when /\A\/stop(@|$)/
            user = Telegram::Helpers::UserLookup.find_user(chat_id)
            Telegram::Chat::Flow.stop(chat_id, user) if user
            return
          when /\A\/create_game(@|$)/
            Telegram::Flows::Games::Manage::CreateFlow.start_create_game(chat_id)
            return
          when /\A\/create_court(@|$)/
            Telegram::Flows::CourtCreateFlow.start(chat_id)
            return
          when /\A\/all_games(@|$)/
            list = Game.includes(:user).order(id: :desc).limit(20).map { |g| game_line_for_command(g) }.join("\n")
            Api.send_simple(chat_id, list.presence || t.(:no_games_on_page))
            return
          when /\A\/my_games(@|$)/
            user = Telegram::Helpers::UserLookup.find_user(chat_id)
            if user
              list = user.games.includes(:user).order(id: :desc).limit(20).map { |g| game_line_for_command(g) }.join("\n")
              Api.send_simple(chat_id, list.presence || t.(:no_games_on_page))
            else
              Api.send_simple(chat_id, t.(:user_not_found))
            end
            return
          end
        end

        # Режим чата стоит выше диалогов: ключи tg:conv живут два часа, и
        # брошенный когда-то мастер не должен глотать сообщения в игру. Но ниже
        # команд — команды бота не ретранслируются никогда.
        return if Telegram::Chat::Relay.handle_message(message)

        key = "tg:conv:#{chat_id}"
        conv = Rails.cache.read(key) || {}

        if conv["step"]
          text = message["text"].to_s.strip
          if text.blank?
            Api.send_force_reply(chat_id, conv["prompt"] || t.(:please_reply))
            return
          end

          if text.downcase == "skip"
            conv["fields"] ||= {}
            conv["fields"][conv["step"]] = nil
          else
            case conv["step"]
            when "singles_hours", "doubles_hours"
              unless text.match?(/\A\d+(\.\d+)?\z/)
                Api.send_force_reply(chat_id, t.(:stats_reply_number))
                return
              end
              conv["fields"] ||= {}
              conv["fields"][conv["step"]] = text.to_f
            when "singles_games", "singles_wins", "doubles_games", "doubles_wins", "aces", "double_faults"
              unless text.match?(/\A\d+\z/)
                Api.send_force_reply(chat_id, t.(:stats_reply_integer))
                return
              end
              conv["fields"] ||= {}
              conv["fields"][conv["step"]] = text.to_i
            when "first_serve_pct"
              unless text.match?(/\A\d+(\.\d+)?\z/) && text.to_f.between?(0, 100)
                Api.send_force_reply(chat_id, t.(:stats_reply_percent))
                return
              end
              conv["fields"] ||= {}
              conv["fields"][conv["step"]] = text.to_f
            else
              Api.send_simple(chat_id, t.(:unexpected_step))
              Rails.cache.delete(key)
              return
            end
          end

          steps = %w[
            singles_hours doubles_hours
            singles_games singles_wins
            doubles_games doubles_wins
            aces double_faults first_serve_pct
          ]
          idx = steps.index(conv["step"]) || -1
          next_step = steps[idx + 1]

          if next_step
            conv["step"] = next_step
            conv["prompt"] = prompt_for(next_step, locale)
            Rails.cache.write(key, conv, expires_in: 2.hours)
            Api.send_force_reply(chat_id, conv["prompt"])
            return
          end

          fields = conv["fields"] || {}
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          unless user
            Api.send_simple(chat_id, t.(:stats_user_not_found))
            Rails.cache.delete(key)
            return
          end

          ps = user.player_statistic || user.create_player_statistic!
          ps.with_lock do
            ps.update!(
              singles_hours: (ps.singles_hours.to_f + (fields["singles_hours"].to_f)).round(2),
              doubles_hours: (ps.doubles_hours.to_f + (fields["doubles_hours"].to_f)).round(2),
              singles_sessions: ps.singles_sessions.to_i + 1,
              singles_games: ps.singles_games.to_i + fields["singles_games"].to_i,
              singles_wins: ps.singles_wins.to_i + fields["singles_wins"].to_i,
              singles_losses: ps.singles_losses.to_i + (fields["singles_games"].to_i - fields["singles_wins"].to_i),
              doubles_games: ps.doubles_games.to_i + fields["doubles_games"].to_i,
              doubles_wins: ps.doubles_wins.to_i + fields["doubles_wins"].to_i,
              doubles_losses: ps.doubles_losses.to_i + (fields["doubles_games"].to_i - fields["doubles_wins"].to_i),
              aces: ps.aces.to_i + fields["aces"].to_i,
              double_faults: ps.double_faults.to_i + fields["double_faults"].to_i,
              first_serve_percent: (fields["first_serve_pct"].nil? ? ps.first_serve_percent : fields["first_serve_pct"].to_f)
            )
          end

          Api.send_simple(chat_id, t.(:stats_recorded))
          Rails.cache.delete(key)
          return
        end

        Rails.logger.info("[Telegram::MessageHandler] Unhandled message from #{chat_id}: #{message.keys}")
      rescue => e
        Rails.logger.error("[Telegram::MessageHandler] #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}")
        Api.send_simple(chat_id, Telegram::I18n.t(:processing_error)) rescue nil
      end

      def self.prompt_for(step, locale = "ru")
        key = case step
        when "singles_hours"  then :stats_reply_singles_hours
        when "doubles_hours"  then :stats_reply_doubles_hours
        when "singles_games"  then :stats_reply_singles_games
        when "singles_wins"   then :stats_reply_singles_wins
        when "doubles_games"  then :stats_reply_doubles_games
        when "doubles_wins"   then :stats_reply_doubles_wins
        when "aces"           then :stats_reply_aces
        when "double_faults"  then :stats_reply_double_faults
        when "first_serve_pct" then :stats_reply_first_serve_pct
        else :please_reply
        end
        Telegram::I18n.t(key, locale: locale)
      end

      def self.game_line_for_command(g)
        when_str = Telegram::Helpers::GameFormatting.game_datetime(g)
        sport = (g.respond_to?(:sport) ? g.sport.to_s.strip.presence : nil)
        owner = g.respond_to?(:user) && g.user ? Telegram::Helpers::UserLookup.display_name(g.user, fallback: nil) : nil

        parts = []
        parts << "#{g.id}:"
        parts << sport if sport.present?
        parts << owner if owner.present?
        parts << when_str if when_str.present?
        parts.join(" ")
      end
    end
  end
end
