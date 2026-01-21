module Telegram
  module Flows
    class ProfileFlow
      class << self
        def handle_callback(callback)
          data = (callback["data"] || "").to_s
          cb_id = callback["id"]
          from = callback["from"] || {}
          chat_id = (callback.dig("message","chat","id") || from["id"]).to_s
          Rails.logger.info "[Telegram::Flows::ProfileFlow] handle_callback data=#{data.inspect} chat_id=#{chat_id} cb_id=#{cb_id}"
          poller = Telegram::Poller.new

          case data
          when /\Aprofile:field:coach:(yes|no|cancel)\z/
            action = Regexp.last_match(1)
            Rails.logger.info "[Telegram::Flows::ProfileFlow] profile:field:coach -> action=#{action} chat_id=#{chat_id}"
            Profile::FieldFlow.process_coach_callback(chat_id, action, cb_id: cb_id, message_id: callback.dig("message","message_id"))
            return
          when /\Aprofile:field:notify:(yes|no|cancel)\z/
            action = Regexp.last_match(1)
            Rails.logger.info "[Telegram::Flows::ProfileFlow] profile:field:notify -> action=#{action} chat_id=#{chat_id}"
            Profile::FieldFlow.process_notify_callback(chat_id, action, cb_id: cb_id, message_id: callback.dig("message","message_id"))
            return
          when /\Aprofile:sports:(toggle|save|cancel|level|level_set|save_levels)(?::(.+))?\z/
            action = Regexp.last_match(1)
            arg = Regexp.last_match(2)
            Rails.logger.info "[Telegram::Flows::ProfileFlow] profile:sports -> action=#{action} arg=#{arg.inspect} chat_id=#{chat_id}"
            Profile::SportsFlow.process_sports_callback(chat_id, action, (arg && CGI.unescape(arg)), cb_id: cb_id, message_id: callback.dig("message","message_id"))
            return
          when /\Aprofile:show\z/
            Rails.logger.info "[Telegram::Flows::ProfileFlow] profile:show -> show_profile(#{chat_id})"
            message_id = callback.dig("message","message_id")
            Telegram::Handlers::ProfileHandler.show_profile(chat_id, message_id: message_id)
            poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
            return
          when /\Aprofile:edit\z/
            Rails.logger.info "[Telegram::Flows::ProfileFlow] profile:edit -> start_edit_profile(#{chat_id})"
            message_id = callback.dig("message","message_id")
            start_edit_profile(chat_id, cb_id: cb_id, message_id: message_id)
            return
          when /\Aprofile:field:(\w+)\z/
            field = Regexp.last_match(1)
            Rails.logger.info "[Telegram::Flows::ProfileFlow] profile:field -> field=#{field} chat_id=#{chat_id}"
            message_id = callback.dig("message","message_id")

            # handle cancel callback (Back button)
            if field == "cancel"
              begin
                Rails.cache.delete("tg:conv:#{chat_id}")
              rescue => e
                Rails.logger.error "[Telegram::Flows::ProfileFlow] profile:field:cancel cache delete failed for chat=#{chat_id}: #{e.class}: #{e.message}"
              end

              Telegram::Api.edit_message_with_buttons(
                chat_id,
                message_id,
                "Edit cancelled.",
                [[{ text: "Edit profile", callback_data: "profile:edit" }]]
              ) rescue nil

              Telegram::Api.answer_callback(cb_id) rescue nil
              return
            end

            Profile::FieldFlow.start_edit_field(chat_id, field, cb_id: cb_id, message_id: message_id)
            return
          else
            poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Unknown profile action", show_alert: false }) rescue nil
            return
          end
        rescue => e
          Rails.logger.error "[Telegram::Flows::ProfileFlow] callback error: #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
        end

        # keep small overview/menu here
        def start_edit_profile(chat_id, cb_id: nil, message_id: nil)
          begin
            user = User.find_by(telegram_chat_id: chat_id.to_s)
          rescue => e
            Rails.logger.error "[Telegram::Flows::ProfileFlow] start_edit_profile: DB error while finding user for chat=#{chat_id}: #{e.class}: #{e.message}"
            return Telegram::Api.answer_callback(cb_id, "Internal error", show_alert: true)
          end
          unless user
            Rails.logger.info "[Telegram::Flows::ProfileFlow] start_edit_profile: no linked user for chat=#{chat_id}"
            return Telegram::Api.answer_callback(cb_id, "No linked account", show_alert: false)
          end

          presenter = Telegram::Presenters::ProfilePresenter.new(user)
          text = [
            "*Edit profile*",
            "Email: #{presenter.email_label}",
            "Sports: #{presenter.sports_label}",
            "City: #{presenter.city_label}",
            "Coach: #{presenter.coach_label}",
            "Notify nearby searches: #{presenter.notify_label}",
            "",
            "Select field to edit:"
          ].join("\n")

          buttons = [
            [{ text: "Email", callback_data: "profile:field:email" }],
            [{ text: "Sports", callback_data: "profile:field:sports" }],
            [{ text: "City", callback_data: "profile:field:city" }],
            [{ text: "Coach", callback_data: "profile:field:coach" }],
            [{ text: "Notify", callback_data: "profile:field:notify" }],
            [{ text: "Back", callback_data: "profile:show" }]
          ]

          if message_id
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons) rescue nil
            Telegram::Api.answer_callback(cb_id) rescue nil
          else
            Telegram::Api.send_with_buttons(chat_id, text, buttons) rescue nil
            Telegram::Api.answer_callback(cb_id) rescue nil
          end
        end

        # delegate reply handling to FieldFlow
        def process_profile_field_reply(message)
          Profile::FieldFlow.process_profile_field_reply(message)
        end
      end
    end
  end
end
