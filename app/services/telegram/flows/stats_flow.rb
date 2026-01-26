module Telegram
  module Flows
    class StatsFlow
      class << self
        # Публично: чтобы StatsFieldInputFlow мог вернуть пользователя в меню
        def render_menu_for(chat_id)
          render_menu(chat_id)
        end

        def handle_callback(callback_query)
          data = (callback_query["data"] || "").to_s
          cb_id = callback_query["id"]
          from = callback_query["from"] || {}
          chat_id = (callback_query.dig("message", "chat", "id") || from["id"]).to_s
          message_id = callback_query.dig("message", "message_id") || callback_query["inline_message_id"]
          return if chat_id.blank? || data.blank?

          case data
          when /\Atg_fill:(\d+)(?::(\d+))?\z/
            game_id = Regexp.last_match(1).to_i
            page = (Regexp.last_match(2) || "1").to_i
            start_menu(chat_id, message_id, cb_id, game_id, page: page)
            return

          when /\Atg_fill_field:(\d+):([a-z_]+)\z/
            game_id = Regexp.last_match(1).to_i
            field = Regexp.last_match(2)

            Telegram::Flows::StatsFieldInputFlow.start(
              chat_id: chat_id,
              message_id: message_id,
              cb_id: cb_id,
              game_id: game_id,
              field: field
            )
            return

          when /\Atg_fill_skip:(\d+):([a-z_]+)\z/
            game_id = Regexp.last_match(1).to_i
            field = Regexp.last_match(2)
            set_field(chat_id, cb_id, game_id, field, nil, skipped: true)
            render_menu(chat_id)
            Telegram::Api.answer_callback(cb_id) rescue nil
            return

          when /\Atg_fill_back:(\d+)\z/
            game_id = Regexp.last_match(1).to_i
            ensure_menu_flow(chat_id, message_id, game_id)
            render_menu(chat_id)
            Telegram::Api.answer_callback(cb_id) rescue nil
            return

          when /\Atg_fill_save:(\d+)\z/
            game_id = Regexp.last_match(1).to_i
            save_to_creator_stats(chat_id, cb_id, game_id)
            return

          when /\Atg_fill_cancel:(\d+)\z/
            game_id = Regexp.last_match(1).to_i
            back_to_game_card(chat_id, cb_id, game_id)
            return
          end

          nil
        rescue => e
          Rails.logger.error "[Telegram::Flows::StatsFlow] handle_callback error: #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
          Telegram::Api.answer_callback(cb_id, "Error.", show_alert: true) rescue nil
          nil
        end

        private

        def fields
          StatisticsPresenter.fields
        end

        def field_def(field)
          StatisticsPresenter.field_def(field)
        end

        def field_example(field)
          StatisticsPresenter.field_example(field)
        end

        def parse_value(field, text)
          f = field_def(field)
          return :invalid unless f

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
          Rails.logger.error "[Telegram::Flows::StatsFlow] Conversation.get failed chat_id=#{chat_id}: #{e.class}: #{e.message}"
          {}
        end

        def safe_conv_set(chat_id, payload)
          Telegram::Helpers::Conversation.set(chat_id, payload)
        rescue => e
          Rails.logger.error "[Telegram::Flows::StatsFlow] Conversation.set failed chat_id=#{chat_id} payload_keys=#{payload.keys.inspect}: #{e.class}: #{e.message}"
          false
        end

        def start_menu(chat_id, message_id, cb_id, game_id, page:)
          game = Game.find_by(id: game_id)
          unless game
            Telegram::Api.answer_callback(cb_id, "Game not found.", show_alert: true) rescue nil
            return
          end

          user = User.find_by(telegram_chat_id: chat_id.to_s) rescue nil
          unless user && (user.admin? || user.id == game.user_id)
            Telegram::Api.answer_callback(cb_id, "Only the game creator or an admin can fill statistics.", show_alert: true) rescue nil
            return
          end

          unless game.started_for_ui?
            start_at = game.start_at_for_ui
            tz = game.creator_time_zone
            msg =
              if start_at
                "Statistics will be available after the game starts: #{start_at.strftime("%Y-%m-%d %H:%M")} (#{tz})"
              else
                "Statistics will be available after the game starts."
              end
            Telegram::Api.answer_callback(cb_id, msg, show_alert: true) rescue nil
            return
          end

          conv = safe_conv_get(chat_id)

          saved_entry = PlayerStatisticEntry.find_by(user: game.user, game: game, source: "telegram")
          saved_fields = (saved_entry&.data || {}).stringify_keys

          entered =
            if conv.is_a?(Hash) && conv["game_id"].to_i == game_id && conv["fields"].is_a?(Hash)
              conv["fields"]
            else
              saved_fields
            end

          safe_conv_set(
            chat_id,
            {
              "flow" => "game_stats_menu",
              "game_id" => game_id,
              "page" => page.to_i,
              "message_id" => message_id,
              "fields" => entered
            }
          )

          render_menu(chat_id, game_id: game_id, message_id: message_id, entered: entered)
          Telegram::Api.answer_callback(cb_id) rescue nil
        end

        def render_menu(chat_id, game_id: nil, message_id: nil, entered: nil)
          conv = safe_conv_get(chat_id)
          game_id = game_id.presence || conv["game_id"]
          message_id = message_id.presence || conv["message_id"]
          entered = entered.is_a?(Hash) ? entered : (conv["fields"].is_a?(Hash) ? conv["fields"] : {})

          game_id = game_id.to_i
          field_defs = fields

          lines = []
          lines << "*Statistics*"
          lines << "Game ##{game_id}"
          lines << ""
          lines << "Entered values (saved immediately):"

          field_defs.each do |f|
            key = f[:key].to_s
            v = entered.key?(key) ? entered[key] : nil
            shown = v.nil? ? "—" : v.to_s
            lines << "• #{f[:label]}: #{shown}"
          end

          text = lines.join("\n")

          field_buttons = field_defs.map do |f|
            [{ text: f[:label], callback_data: "tg_fill_field:#{game_id}:#{f[:key]}" }]
          end

          footer = [
            [{ text: "Back", callback_data: "tg_fill_cancel:#{game_id}" }]
          ]

          if message_id.present?
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, field_buttons + footer) rescue nil
          else
            Telegram::Api.send_with_buttons(chat_id, text, field_buttons + footer) rescue nil
          end
        end

        def save_to_creator_stats(chat_id, cb_id, game_id)
          game = Game.find_by(id: game_id)
          unless game
            Telegram::Api.answer_callback(cb_id, "Game not found.", show_alert: true) rescue nil
            return
          end

          actor = User.find_by(telegram_chat_id: chat_id.to_s) rescue nil
          unless actor && (actor.admin? || actor.id == game.user_id)
            Telegram::Api.answer_callback(cb_id, "Only the game creator or an admin can fill statistics.", show_alert: true) rescue nil
            return
          end

          unless game.started_for_ui?
            Telegram::Api.answer_callback(cb_id, "Statistics is locked until the game starts.", show_alert: true) rescue nil
            return
          end

          conv = Telegram::Helpers::Conversation.get(chat_id) rescue {}
          entered = (conv.is_a?(Hash) && conv["fields"].is_a?(Hash)) ? conv["fields"] : {}

          data = {}
          fields.each do |f|
            key = f[:key].to_s
            next unless entered.key?(key)
            val = entered[key]
            next if val.nil?
            data[key] = val
          end

          recorded_at = Time.current

          PlayerStatistics::ApplyEntryToParticipantsService.new(
            game: game,
            actor: actor,
            data: data,
            source: "telegram",
            recorded_at: recorded_at,
            include_creator: true
          ).call

          Telegram::Api.answer_callback(cb_id, "Saved.", show_alert: false) rescue nil
          back_to_game_card(chat_id, nil, game_id, keep_conv: false)
        rescue ActiveRecord::RecordNotUnique
          Telegram::Api.answer_callback(cb_id, "Already saved for this game.", show_alert: true) rescue nil
        rescue => e
          Rails.logger.error "[Telegram::Flows::StatsFlow] save_to_creator_stats error: #{e.class}: #{e.message}"
          Telegram::Api.answer_callback(cb_id, "Save failed.", show_alert: true) rescue nil
        end

        def back_to_game_card(chat_id, cb_id, game_id, keep_conv: true)
          conv = Telegram::Helpers::Conversation.get(chat_id) rescue {}
          page = (conv.is_a?(Hash) && conv["page"].to_i > 0) ? conv["page"].to_i : 1
          message_id = conv.is_a?(Hash) ? conv["message_id"] : nil

          Telegram::Helpers::Conversation.finish(chat_id) rescue nil unless keep_conv

          Telegram::Handlers::GamesHandler.show_game(chat_id, game_id, page, message_id: message_id) rescue nil
          Telegram::Api.answer_callback(cb_id) rescue nil if cb_id
        end

        def ensure_menu_flow(chat_id, message_id, game_id)
          conv = Telegram::Helpers::Conversation.get(chat_id) rescue {}
          entered_fields = (conv.is_a?(Hash) && conv["fields"].is_a?(Hash)) ? conv["fields"] : {}
          page = (conv.is_a?(Hash) && conv["page"].to_i > 0) ? conv["page"].to_i : 1

          safe_conv_set(
            chat_id,
            {
              "flow" => "game_stats_menu",
              "game_id" => game_id,
              "page" => page,
              "message_id" => message_id || (conv.is_a?(Hash) ? conv["message_id"] : nil),
              "fields" => entered_fields
            }
          )
        end

        def set_field(chat_id, _cb_id, game_id, field, value, skipped:)
          conv = Telegram::Helpers::Conversation.get(chat_id) rescue {}
          entered = (conv.is_a?(Hash) && conv["fields"].is_a?(Hash)) ? conv["fields"] : {}
          return unless field_def(field)

          key = field.to_s
          entered[key] = skipped ? nil : value

          safe_conv_set(
            chat_id,
            (conv.is_a?(Hash) ? conv.merge("fields" => entered, "game_id" => game_id) : { "fields" => entered, "game_id" => game_id })
          )
        end
      end
    end
  end
end
