module Telegram
  module Flows
    module Profile
      module FieldFlow
        module_function

        def start_edit_field(chat_id, field, cb_id: nil, message_id: nil)
          begin
            user = User.find_by(telegram_chat_id: chat_id.to_s)
          rescue => e
            Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] start_edit_field: DB error finding user for chat=#{chat_id}: #{e.class}: #{e.message}"
            return Telegram::Api.answer_callback(cb_id, "Internal error", show_alert: true)
          end
          unless user
            Rails.logger.info "[Telegram::Flows::Profile::FieldFlow] start_edit_field: no linked user for chat=#{chat_id}"
            return Telegram::Api.answer_callback(cb_id, "No linked account", show_alert: false)
          end

          presenter = Telegram::Presenters::ProfilePresenter.new(user)

          # handle sports as interactive multi-select
          if field.to_s == "sports"
            selections = Array(presenter.sports_label == "—" ? [] : (user.respond_to?(:preferred_sports) ? user.preferred_sports : (user.sports.to_s.split(",").map(&:strip))))
            conv = { "flow" => "profile_sports", "selections" => selections, "created_at" => Time.current }
            begin
              Rails.cache.write("tg:conv:#{chat_id}", conv, expires_in: 2.hours)
            rescue => e
              Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] start_edit_field: cache write failed for chat=#{chat_id}: #{e.class}: #{e.message}"
            end

            buttons = User::SPORTS.map do |s|
              label = selections.include?(s) ? "✓ #{s}" : s
              [{ text: label, callback_data: "profile:sports:toggle:#{CGI.escape(s)}" }]
            end
            buttons << [{ text: "Save", callback_data: "profile:sports:save" }, { text: "Back", callback_data: "profile:sports:cancel" }]

            text = "PROFILE_FIELD_PROMPT:sports\nEditing: sports\nCurrent: #{selections.any? ? selections.join(', ') : '—'}\nSelect sports (multiple) and press Save or Back."

            if message_id
              Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons) rescue nil
              Telegram::Api.answer_callback(cb_id) rescue nil
            else
              Telegram::Api.send_with_buttons(chat_id, text, buttons) rescue nil
              Telegram::Api.answer_callback(cb_id) rescue nil
            end

            return
          end

          # handle notify as inline checkbox (Yes/No)
          if field.to_s == "notify"
            conv = { "flow" => "profile_field", "field" => "notify", "created_at" => Time.current }
            begin
              Rails.cache.write("tg:conv:#{chat_id}", conv, expires_in: 10.minutes)
            rescue => e
              Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] start_edit_field: cache write failed for chat=#{chat_id}: #{e.class}: #{e.message}"
            end

            current = presenter.current_value_for("notify")
            buttons = [
              [{ text: "Yes", callback_data: "profile:field:notify:yes" }],
              [{ text: "No",  callback_data: "profile:field:notify:no"  }],
              [{ text: "Back", callback_data: "profile:field:cancel" }]
            ]
            text = "PROFILE_FIELD_PROMPT:notify\nEditing: notify\nCurrent: #{current}\nChoose Yes or No or press Back."

            if message_id
              Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons) rescue nil
              Telegram::Api.answer_callback(cb_id) rescue nil
            else
              Telegram::Api.send_with_buttons(chat_id, text, buttons) rescue nil
              Telegram::Api.answer_callback(cb_id) rescue nil
            end

            return
          end

          # handle coach as inline checkbox (Yes/No) — same UX as notify
          if field.to_s == "coach"
            conv = { "flow" => "profile_field", "field" => "coach", "created_at" => Time.current }
            begin
              Rails.cache.write("tg:conv:#{chat_id}", conv, expires_in: 10.minutes)
            rescue => e
              Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] start_edit_field: cache write failed for chat=#{chat_id}: #{e.class}: #{e.message}"
            end

            current = presenter.current_value_for("coach")
            buttons = [
              [{ text: "Yes", callback_data: "profile:field:coach:yes" }],
              [{ text: "No",  callback_data: "profile:field:coach:no"  }],
              [{ text: "Back", callback_data: "profile:field:cancel" }]
            ]
            text = "PROFILE_FIELD_PROMPT:coach\nEditing: coach\nCurrent: #{current}\nChoose Yes or No or press Back."

            if message_id
              Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons) rescue nil
              Telegram::Api.answer_callback(cb_id) rescue nil
            else
              Telegram::Api.send_with_buttons(chat_id, text, buttons) rescue nil
              Telegram::Api.answer_callback(cb_id) rescue nil
            end

            return
          end

          # normal single-field flow
          begin
            Rails.cache.write("tg:conv:#{chat_id}", { "flow" => "profile_field", "field" => field, "created_at" => Time.current }, expires_in: 10.minutes)
          rescue => e
            Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] start_edit_field: cache write failed for chat=#{chat_id}: #{e.class}: #{e.message}"
          end
          current = presenter.current_value_for(field)
          text = "PROFILE_FIELD_PROMPT:#{field}\nEditing: #{field}\nCurrent: #{current}\nSend new value or press Back to cancel."

          if message_id
            buttons = [[{ text: "Back", callback_data: "profile:field:cancel" }]]
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons) rescue nil
            Telegram::Api.answer_callback(cb_id) rescue nil
          else
            Telegram::Api.send_simple(chat_id, text) rescue nil
            Telegram::Api.answer_callback(cb_id) rescue nil
          end
        end

        def process_profile_field_reply(message)
          chat = message["chat"] || {}
          chat_id = (chat["id"] || message.dig("from","id")).to_s
          text = message["text"].to_s.strip
          Rails.logger.info "[Telegram::Flows::Profile::FieldFlow] process_profile_field_reply chat_id=#{chat_id} text=#{text.inspect} reply_to=#{message.dig('reply_to_message','text').to_s.inspect}"
          return unless text.present?

          begin
            conv = Rails.cache.read("tg:conv:#{chat_id}") || {}
          rescue => e
            Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] process_profile_field_reply: cache read failed for chat=#{chat_id}: #{e.class}: #{e.message}"
            conv = {}
          end
          field = conv && conv["field"]
          unless field
            Rails.logger.info "[Telegram::Flows::Profile::FieldFlow] no conv field for chat #{chat_id}"
            return Telegram::Api.send_simple(chat_id, "No pending field edit.")
          end

          if text.downcase == "back"
            begin
              Rails.cache.delete("tg:conv:#{chat_id}")
            rescue => e
              Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] process_profile_field_reply: cache delete failed for chat=#{chat_id}: #{e.class}: #{e.message}"
            end
            return Telegram::Api.send_simple(chat_id, "Edit cancelled.")
          end

          user = User.find_by(telegram_chat_id: chat_id.to_s) rescue nil
          return Telegram::Api.send_simple(chat_id, "No linked account.") unless user

          case field
          when "email"
            if text.present?
              taken = User.where('LOWER("users"."email") = LOWER(?)', text)
                          .where.not(id: user.id)
                          .exists?
              if taken
                Rails.logger.info "[Telegram::Flows::Profile::FieldFlow] email already taken chat_id=#{chat_id} email=#{text}"
                return Telegram::Api.send_simple(chat_id, "This email is already used by another account.")
              end
            end

            user.email = text if user.respond_to?(:email=)
            user.timezone = nil if user.respond_to?(:timezone=)
          when "city"
            # persist the user-visible city name immediately (transliterate for plain text)
            translit_input = translit_str(text)
            user.city_name = translit_input if user.respond_to?(:city_name=)
            user.location = text if user.respond_to?(:location=)
            # clear timezone so ResolveUserCityJob can recompute it
            if user.respond_to?(:timezone=)
              user.timezone = nil
              Rails.logger.info "[Telegram::Flows::Profile::FieldFlow] cleared timezone for user_id=#{user.id} to allow async resolution"
            end
          when "notify"
            val = (text.downcase == 'yes' || text == '1' || text.downcase == 'true')
            user.notify_nearby = val if user.respond_to?(:notify_nearby=)
            user.notify = val if user.respond_to?(:notify=)
          else
            return Telegram::Api.send_simple(chat_id, "Unknown field.")
          end

          begin
            if user.save
              begin
                Rails.cache.delete("tg:conv:#{chat_id}")
              rescue => e
                Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] process_profile_field_reply: cache delete failed for chat=#{chat_id}: #{e.class}: #{e.message}"
              end
              Rails.logger.info "[Telegram::Flows::Profile::FieldFlow] field #{field} updated user_id=#{user.id}"
              ResolveUserCityJob.perform_later(user.id, text) if field == "city" && text.present?
              Telegram::Api.send_simple(chat_id, "Field updated.")
              # immediately refresh profile view so user sees new city
              Telegram::Handlers::ProfileHandler.show_profile(chat_id) rescue nil
            else
              if user.errors.any?
                msgs = user.errors.full_messages.join(", ")
                Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] profile field validation failed user_id=#{user.id} errors=#{msgs.inspect} details=#{user.errors.details.inspect}"
                Telegram::Api.send_simple(chat_id, "Failed to update field: #{msgs}")
              else
                Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] profile field validation failed user_id=#{user.id} (no validation messages)"
                Telegram::Api.send_simple(chat_id, "Failed to update field: Validation failed")
              end
            end
          rescue ActiveRecord::RecordNotUnique => e
            Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] DB unique constraint failed: #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}"
            Telegram::Api.send_simple(chat_id, "Value conflicts with another record (unique constraint).")
          rescue => e
            Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] profile field save exception user_id=#{user&.id} #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}\nuser_errors=#{user&.errors&.full_messages&.inspect} details=#{user&.errors&.details&.inspect}"
            Telegram::Api.send_simple(chat_id, "Failed to update field: #{(user&.errors&.full_messages&.join(', ').presence || "#{e.class}: #{e.message}")}")
          end
        end

        def process_notify_callback(chat_id, action, cb_id: nil, message_id: nil)
          begin
            user = User.find_by(telegram_chat_id: chat_id.to_s)
          rescue => e
            Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] process_notify_callback: DB error for chat=#{chat_id}: #{e.class}: #{e.message}"
            return Telegram::Api.answer_callback(cb_id, "Internal error", show_alert: true)
          end
          unless user
            Rails.logger.info "[Telegram::Flows::Profile::FieldFlow] process_notify_callback: no linked user for chat=#{chat_id}"
            return Telegram::Api.answer_callback(cb_id, "No linked account", show_alert: false)
          end

          if action == "cancel"
            begin
              Rails.cache.delete("tg:conv:#{chat_id}")
            rescue => e
              Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] process_notify_callback: cache delete failed for chat=#{chat_id}: #{e.class}: #{e.message}"
            end
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, "Edit cancelled.", [[{ text: "Edit profile", callback_data: "profile:edit" }]]) rescue nil
            Telegram::Api.answer_callback(cb_id) rescue nil
            return
          end

          val = (action == "yes")
          user.notify_nearby = val if user.respond_to?(:notify_nearby=)
          user.notify = val if user.respond_to?(:notify=)

          if user.save
            begin
              Rails.cache.delete("tg:conv:#{chat_id}")
            rescue => e
              Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] process_notify_callback: cache delete failed for chat=#{chat_id}: #{e.class}: #{e.message}"
            end
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, "*Edit profile*\nNotify nearby searches: #{val ? 'Yes' : 'No'}", [[{ text: "Edit profile", callback_data: "profile:edit" }]]) rescue nil
            Telegram::Api.answer_callback(cb_id) rescue nil
          else
            Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] failed saving notify for user_id=#{user.id} errors=#{user.errors.full_messages.join(', ')}"
            Telegram::Api.answer_callback(cb_id, "Failed to save", show_alert: true) rescue nil
          end
        end

        def process_coach_callback(chat_id, action, cb_id: nil, message_id: nil)
          begin
            user = User.find_by(telegram_chat_id: chat_id.to_s)
          rescue => e
            Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] process_coach_callback: DB error for chat=#{chat_id}: #{e.class}: #{e.message}"
            return Telegram::Api.answer_callback(cb_id, "Internal error", show_alert: true)
          end
          unless user
            Rails.logger.info "[Telegram::Flows::Profile::FieldFlow] process_coach_callback: no linked user for chat=#{chat_id}"
            return Telegram::Api.answer_callback(cb_id, "No linked account", show_alert: false)
          end

          if action == "cancel"
            begin
              Rails.cache.delete("tg:conv:#{chat_id}")
            rescue => e
              Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] process_coach_callback: cache delete failed for chat=#{chat_id}: #{e.class}: #{e.message}"
            end
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, "Edit cancelled.", [[{ text: "Edit profile", callback_data: "profile:edit" }]]) rescue nil
            Telegram::Api.answer_callback(cb_id) rescue nil
            return
          end

          val = (action == "yes")
          user.coach = val if user.respond_to?(:coach=)
          if user.save
            begin
              Rails.cache.delete("tg:conv:#{chat_id}")
            rescue => e
              Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] process_coach_callback: cache delete failed for chat=#{chat_id}: #{e.class}: #{e.message}"
            end
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, "*Edit profile*\nCoach: #{val ? 'Yes' : 'No'}", [[{ text: "Edit profile", callback_data: "profile:edit" }]]) rescue nil
            Telegram::Api.answer_callback(cb_id) rescue nil
          else
            Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] failed saving coach for user_id=#{user.id} errors=#{user.errors.full_messages.join(', ')}"
            Telegram::Api.answer_callback(cb_id, "Failed to save", show_alert: true) rescue nil
          end
        end

        private

        def self.translit_str(s)
          Russian.translit(s.to_s)
        end
      end
    end
  end
end
