module Telegram
  module Handlers
    class GameDetailHandler
      class << self
        include Telegram::Handlers::ReplyHelpers

        def show_game(chat_id, game_id, page = 1, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          Rails.logger.debug "[Telegram::Handlers::GameDetailHandler] show_game chat=#{chat_id} game_id=#{game_id} page=#{page} msg_id=#{message_id}"
          game = Game.find_by(id: game_id)
          return Telegram::Api.send_simple(chat_id, t.(:game_not_found)) unless game

          participants_count =
            if game.respond_to?(:participations)
              game.participations.respond_to?(:approved) ? game.participations.approved.size : game.participations.size
            else
              0
            end
          capacity = (game.respond_to?(:players_count) && game.players_count.to_i > 0) ? game.players_count.to_i : "?"
          players_line = t.(:players, count: participants_count, capacity: capacity)
          owner = User.find_by(id: game.user_id) rescue nil
          owner_name = Telegram::Helpers::UserLookup.display_name(owner, fallback: owner&.telegram_chat_id || "—")
          owner_line = t.(:owner, name: owner_name)

          host = ENV.fetch("APP_HOST", "https://getcourt.co")
          game_url = Rails.application.routes.url_helpers.game_url(game, host: host)

          lines = []
          title = Telegram::Helpers::GameFormatting.game_title(game, locale: locale)
          title_text = "#{title || 'Game'} ##{game.id}"
          lines << "*#{title_text}*"

          coach = Telegram::Helpers::GameFormatting.coach_mark(game, locale: locale)
          lines << t.(:coach_label, value: coach) if coach.present?

          when_str = Telegram::Helpers::GameFormatting.game_datetime(game, locale: locale)
          lines << t.(:when_label, datetime: when_str) if when_str.present?

          reading = Weather::GoogleForecast.for_game(game, timeout: { open: 2, read: 3 })
          lines << t.(:weather_label, value: weather_text(reading)) if reading

          lines << players_line
          lines << t.(:court_label, name: game.court&.name) if game.respond_to?(:court) && game.court
          lines << owner_line
          text = lines.compact.join("\n")

          buttons = []

          user = Telegram::Helpers::UserLookup.find_user(chat_id)

          participation = user ? game.participations.find_by(user_id: user.id) : nil
          direct_join = user && (user.admin? || user.id == game.user_id)
          join_btn =
            if participation && participation.respond_to?(:pending?) && participation.pending?
              { text: t.(:request_sent), callback_data: "game:join_pending:#{game.id}" }
            elsif participation
              { text: t.(:leave), callback_data: "game:leave:#{game.id}" }
            else
              label = direct_join ? t.(:join) : t.(:request_to_join)
              { text: label, callback_data: "game:join:#{game.id}" }
            end

          row1 = [ join_btn ]

          # [bot-menu-off] Отключено намеренно: пользуемся сайтом getcourt.co,
          # бот оставлен только для приглашений и карточки игры.
          # Раскомментировать, если решим вернуть функциональность в бот.
          # if game.prebooking_enabled? && (!game.respond_to?(:recurring?) || game.recurring?)
          #   row1 << { text: t.(:prebooking), callback_data: "game:prebook:#{game.id}" }
          # end

          buttons << row1

          buttons << [ { text: t.(:players_list_btn), callback_data: "game:players:#{game.id}:#{page}" } ]

          buttons << [ { text: t.(:open_in_browser), url: game_url } ] unless host.to_s.include?("localhost")

          # [bot-menu-off] Отключено намеренно: пользуемся сайтом getcourt.co,
          # бот оставлен только для приглашений и карточки игры.
          # Раскомментировать, если решим вернуть функциональность в бот.
          # can_fill_stats = can_fill_stats_for_game?(user, game)
          # if game.started_for_ui?
          #   if can_fill_stats
          #     buttons << [ { text: t.(:statistics), callback_data: "tg_fill:#{game.id}:#{page}" } ]
          #   else
          #     buttons << [ { text: t.(:statistics), callback_data: "tg_stats_unauthorized:#{game.id}" } ]
          #   end
          # else
          #   buttons << [ { text: t.(:statistics_locked), callback_data: "tg_stats_locked:#{game.id}" } ]
          # end
          # if user && (user.admin? || user.id == game.user_id)
          #   if game.urgent_player_search?
          #     buttons << [ { text: t.(:urgent_search_disable), callback_data: "game:urgent_search:#{game.id}:off:#{page}" } ]
          #   else
          #     buttons << [ { text: t.(:urgent_search_enable), callback_data: "game:urgent_search:#{game.id}:on:#{page}" } ]
          #   end
          #   buttons << [ { text: t.(:invite_players), callback_data: "game:invite:#{game.id}" } ]
          #   buttons << [ { text: t.(:manage_players), callback_data: "game:manage:#{game.id}:#{page}" } ]
          #   buttons << [ { text: t.(:edit), callback_data: "game:edit:#{game.id}" } ]
          #   buttons << [ { text: t.(:delete), callback_data: "game:delete:#{game.id}:#{page}" } ]
          # end
          # buttons << [ { text: t.(:share_game), callback_data: "game:share:#{game.id}:#{page}" } ]
          # buttons << [ { text: t.(:back_to_games), callback_data: "menu:games:page:#{page}" } ]

          send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
        end

        def show_players(chat_id, game_id, page = 1, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          game = Game.find_by(id: game_id)
          return Telegram::Api.send_simple(chat_id, t.(:game_not_found)) unless game

          participations =
            if game.respond_to?(:participations)
              scope = game.participations.respond_to?(:approved) ? game.participations.approved : game.participations
              scope.includes(:user).to_a
            else
              []
            end

          lines = []
          lines << "*#{t.(:players_list_title, game_id: game.id)}*"
          lines << ""

          if participations.empty?
            lines << t.(:players_list_empty)
          else
            rows = participations.map do |participation|
              if participation.guest?
                { name: "#{participation.guest_name} (#{t.(:guest_badge)})", games: 0, wins: 0, pct: 0.0 }
              else
                u = participation.user
                ps = u.player_statistic
                total_games = ps&.singles_games.to_i + ps&.doubles_games.to_i
                total_wins = ps&.singles_wins.to_i + ps&.doubles_wins.to_i
                pct = total_games > 0 ? (total_wins.to_f / total_games * 100).round(1) : 0.0
                name = u.telegram_username.present? ? "@#{u.telegram_username.delete_prefix('@')}" : (u.name.presence || u.email.presence || "User ##{u.id}")
                { name: name, games: total_games, wins: total_wins, pct: pct }
              end
            end
            rows.sort_by! { |r| [ -r[:pct], -r[:wins], -r[:games] ] }
            rows.each do |r|
              lines << t.(:player_stats_row, name: r[:name], games: r[:games], wins: r[:wins], pct: r[:pct])
            end
          end

          buttons = [
            [ { text: t.(:back_to_game), callback_data: "game:show:#{game.id}:#{page}" } ]
          ]

          send_or_edit_with_buttons(chat_id, lines.join("\n"), buttons, message_id: message_id)
        end

        private

        # [bot-menu-off] Отключено намеренно: пользуемся сайтом getcourt.co,
        # бот оставлен только для приглашений и карточки игры.
        # Раскомментировать, если решим вернуть функциональность в бот.
        # def can_fill_stats_for_game?(user, game)
        #   return false unless user && game
        #   return true if user.admin? || user.id == game.user_id
        #   participations = game.participations
        #   if participations.respond_to?(:approved)
        #     participations.approved.exists?(user_id: user.id)
        #   else
        #     participations.exists?(user_id: user.id, status: "approved")
        #   end
        # end

        def weather_text(reading)
          text = "#{Weather::Icons.for(reading.condition_type)} #{reading.temperature_c.round}°"
          text += " · #{reading.precipitation_percent}%" if reading.precipitation_percent.to_i >= 30
          text
        end
      end
    end
  end
end
