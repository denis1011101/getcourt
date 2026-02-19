module Telegram
  module Flows
    class StatsFieldInputFlow
      class << self
        def start(chat_id:, message_id:, cb_id:, game_id:, field:)
          game = Game.find_by(id: game_id)
          unless game
            Telegram::Api.answer_callback(cb_id, "Game not found.", show_alert: true) rescue nil
            return false
          end

          actor = User.find_by(telegram_chat_id: chat_id.to_s) rescue nil
          unless actor && (actor.admin? || actor.id == game.user_id)
            Telegram::Api.answer_callback(cb_id, "Only the game creator or an admin can fill statistics.", show_alert: true) rescue nil
            return false
          end

          unless game.started_for_ui?
            Telegram::Api.answer_callback(cb_id, "Statistics is locked until the game starts.", show_alert: true) rescue nil
            return false
          end

          auto_hours = field.to_s == "hours"
          effective_field = auto_hours ? StatisticsPresenter.hours_field_for_game(game) : field

          unless StatisticsPresenter.field_def(effective_field)
            Telegram::Api.answer_callback(cb_id, "Unknown field.", show_alert: true) rescue nil
            return false
          end

          conv = safe_conv_get(chat_id)
          entered = (conv.is_a?(Hash) && conv["fields"].is_a?(Hash)) ? conv["fields"] : {}
          page = (conv.is_a?(Hash) && conv["page"].to_i > 0) ? conv["page"].to_i : 1

          safe_conv_set(
            chat_id,
            {
              "flow" => "game_stats_field_input",
              "game_id" => game_id.to_i,
              "field" => effective_field.to_s,
              "auto_hours" => auto_hours,
              "page" => page,
              "message_id" => message_id,
              "fields" => entered
            }
          )

          prompt(chat_id: chat_id, game_id: game_id, field: effective_field, message_id: message_id, auto_hours: auto_hours)
          Telegram::Api.answer_callback(cb_id) rescue nil
          true
        end

        # Возвращает true если сообщение обработано (и больше никому его отдавать не надо)
        def handle_message(message)
          chat_id = message.dig("chat", "id").to_s
          text = (message["text"] || "").to_s
          return false if chat_id.blank? || text.blank?

          conv = safe_conv_get(chat_id)
          return false unless conv.is_a?(Hash)
          return false unless conv["flow"] == "game_stats_field_input"

          game_id = conv["game_id"].to_i
          field = conv["field"].to_s
          return false unless StatisticsPresenter.field_def(field)

          auto_hours = conv["auto_hours"] == true

          parsed = parse_value(field, text)
          if parsed == :invalid
            prompt(chat_id: chat_id, game_id: game_id, field: field, message_id: conv["message_id"], auto_hours: auto_hours)
            return true
          end

          game = Game.find_by(id: game_id)
          actor = User.find_by(telegram_chat_id: chat_id.to_s) rescue nil
          return false unless game && actor

          entry_exists = PlayerStatisticEntry.where(game: game, source: "telegram").exists?
          match_exists = Match.where(game_id: game.id).exists?
          first_entry = false
          if entry_exists == false && match_exists == false
            first_entry = true
          end

          # удалить пользовательское сообщение с числом (может не получиться — ок)
          Telegram::Api.post(
            "deleteMessage",
            { "chat_id" => chat_id.to_s, "message_id" => message["message_id"].to_i }
          ) rescue nil

          # сохранить сразу (upsert одной записи на игру) — ДЛЯ ВСЕХ участников + создателя
          PlayerStatistics::ApplyEntryToParticipantsService.new(
            game: game,
            actor: actor,
            data: { field.to_s => parsed },
            source: "telegram",
            recorded_at: Time.current,
            include_creator: true
          ).call

          if first_entry
            increment_activity_for_game(game)
          end

          # обновить conversation для отображения
          entered = (conv["fields"].is_a?(Hash) ? conv["fields"] : {})
          entered[field.to_s] = parsed

          safe_conv_set(
            chat_id,
            conv.merge("flow" => "game_stats_menu", "fields" => entered, "game_id" => game_id)
          )

          Telegram::Flows::StatsFlow.render_menu_for(chat_id)
          true
        rescue => e
          Rails.logger.error "[Telegram::Flows::StatsFieldInputFlow] handle_message error: #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
          false
        end

        private

        def prompt(chat_id:, game_id:, field:, message_id:, auto_hours: false)
          f = StatisticsPresenter.field_def(field)
          example = StatisticsPresenter.field_example(field)

          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          label =
            if auto_hours
              game = Game.find_by(id: game_id)
              if game
                hours_field = StatisticsPresenter.hours_field_for_game(game)
                t.call(hours_field == :doubles_hours ? :stats_hours_doubles : :stats_hours_singles)
              else
                t.call(:stats_enter_hours_btn)
              end
            else
              f[:label]
            end

          text =
            "*#{t.call(:statistics)}*\n" \
            "#{t.call(:stats_game_label, id: game_id)}\n\n" \
            t.call(:stats_field_enter_value, label: label, example: example)

          keyboard = [
            [ { text: t.call(:back), callback_data: "tg_fill_back:#{game_id}" } ]
          ]

          if message_id.present?
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, keyboard) rescue nil
          else
            Telegram::Api.send_with_buttons(chat_id, text, keyboard) rescue nil
          end
        end

        def parse_value(field, text)
          s = text.to_s.strip
          return :invalid if s.empty?

          case StatisticsPresenter.field_type(field)
          when :float
            s = s.tr(",", ".")
            v = Float(s) rescue nil
            return :invalid if v.nil? || v.negative?
            v.round(2)
          else
            return :invalid unless s.match?(/\A\d+\z/)
            v = s.to_i
            return :invalid if v.negative?
            v
          end
        end

        def safe_conv_get(chat_id)
          Telegram::Helpers::Conversation.get(chat_id)
        rescue => e
          Rails.logger.error "[Telegram::Flows::StatsFieldInputFlow] Conversation.get failed chat_id=#{chat_id}: #{e.class}: #{e.message}"
          {}
        end

        def safe_conv_set(chat_id, payload)
          Telegram::Helpers::Conversation.set(chat_id, payload)
        rescue => e
          Rails.logger.error "[Telegram::Flows::StatsFieldInputFlow] Conversation.set failed chat_id=#{chat_id}: #{e.class}: #{e.message}"
          false
        end

        def increment_activity_for_game(game)
          users = []
          if game.respond_to?(:user)
            users << game.user
          end
          if game.respond_to?(:participations)
            users.concat(game.participations.includes(:user).map(&:user))
          end
          users = users.compact.uniq { |u| u.id }

          mode = StatisticsPresenter.hours_field_for_game(game) == :doubles_hours ? :doubles : :singles

          training_key = nil
          if game.respond_to?(:with_coach?) && game.with_coach?
            if mode == :doubles
              training_key = :group_training
            else
              training_key = :individual_training
            end
          end

          users.each do |u|
            ps = u.player_statistic || u.create_player_statistic
            ps.with_lock do
              if training_key
                ps[training_key] = ps[training_key].to_i + 1
                ps[training_key] = [ ps[training_key].to_i, 0 ].max
              else
                games_key = mode == :doubles ? :doubles_games : :singles_games
                ps[games_key] = ps[games_key].to_i + 1
                ps[games_key] = [ ps[games_key].to_i, 0 ].max
              end
              ps.save!
            end
          end
        rescue => e
          Rails.logger.error "[Telegram::Flows::StatsFieldInputFlow] increment_activity_for_game error: #{e.class}: #{e.message}"
        end
      end
    end
  end
end
