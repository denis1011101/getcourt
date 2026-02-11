module Telegram
  module Flows
    class ProfileFlow
      class << self
        include Telegram::Handlers::ReplyHelpers

        def handle_callback(callback)
          cb = Telegram::Helpers::CallbackData.parse(callback)
          Rails.logger.info "[Telegram::Flows::ProfileFlow] handle_callback data=#{cb.data.inspect} chat_id=#{cb.chat_id} cb_id=#{cb.cb_id}"
          poller = Telegram::Poller.new

          case cb.data
          when /\Aprofile:field:coach:(yes|no|cancel)\z/
            action = Regexp.last_match(1)
            Rails.logger.info "[Telegram::Flows::ProfileFlow] profile:field:coach -> action=#{action} chat_id=#{cb.chat_id}"
            Profile::FieldFlow.process_coach_callback(cb.chat_id, action, cb_id: cb.cb_id, message_id: cb.message_id)
            return
          when /\Aprofile:field:notify:(yes|no|cancel)\z/
            action = Regexp.last_match(1)
            Rails.logger.info "[Telegram::Flows::ProfileFlow] profile:field:notify -> action=#{action} chat_id=#{cb.chat_id}"
            Profile::FieldFlow.process_notify_callback(cb.chat_id, action, cb_id: cb.cb_id, message_id: cb.message_id)
            return
          when /\Aprofile:sports:(toggle|save|cancel|level|level_set|save_levels)(?::(.+))?\z/
            action = Regexp.last_match(1)
            arg = Regexp.last_match(2)
            Rails.logger.info "[Telegram::Flows::ProfileFlow] profile:sports -> action=#{action} arg=#{arg.inspect} chat_id=#{cb.chat_id}"
            Profile::SportsFlow.process_sports_callback(cb.chat_id, action, (arg && CGI.unescape(arg)), cb_id: cb.cb_id, message_id: cb.message_id)
            return
          when /\Aprofile:show\z/
            Rails.logger.info "[Telegram::Flows::ProfileFlow] profile:show -> show_profile(#{cb.chat_id})"
            Telegram::Handlers::ProfileHandler.show_profile(cb.chat_id, message_id: cb.message_id)
            poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil
            return
          when /\Aprofile:edit\z/
            Rails.logger.info "[Telegram::Flows::ProfileFlow] profile:edit -> start_edit_profile(#{cb.chat_id})"
            start_edit_profile(cb.chat_id, cb_id: cb.cb_id, message_id: cb.message_id)
            return
          when /\Aprofile:field:(\w+)\z/
            field = Regexp.last_match(1)
            Rails.logger.info "[Telegram::Flows::ProfileFlow] profile:field -> field=#{field} chat_id=#{cb.chat_id}"

            # handle cancel callback (Back button)
            if field == "cancel"
              Telegram::Helpers::Conversation.finish(cb.chat_id) rescue nil

              Telegram::Api.edit_message_with_buttons(
                cb.chat_id,
                cb.message_id,
                "Edit cancelled.",
                [[{ text: "Edit profile", callback_data: "profile:edit" }]]
              ) rescue nil

              Telegram::Api.answer_callback(cb.cb_id) rescue nil
              return
            end

            Profile::FieldFlow.start_edit_field(cb.chat_id, field, cb_id: cb.cb_id, message_id: cb.message_id)
            return
          else
            poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "Unknown profile action", show_alert: false }) rescue nil
            return
          end
        rescue => e
          Rails.logger.error "[Telegram::Flows::ProfileFlow] callback error: #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
        end

        # keep small overview/menu here
        def start_edit_profile(chat_id, cb_id: nil, message_id: nil)
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
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

          send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
          Telegram::Api.answer_callback(cb_id) rescue nil
        end

        # delegate reply handling to FieldFlow
        def process_profile_field_reply(message)
          Profile::FieldFlow.process_profile_field_reply(message)
        end
      end
    end
  end
end
