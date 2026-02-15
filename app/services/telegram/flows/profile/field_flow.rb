module Telegram
  module Flows
    module Profile
      module FieldFlow
        module_function

        def start_edit_field(chat_id, field, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          begin
            user = User.find_by(telegram_chat_id: chat_id.to_s)
          rescue => e
            Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] start_edit_field: DB error finding user for chat=#{chat_id}: #{e.class}: #{e.message}"
            return Telegram::Api.answer_callback(cb_id, "Internal error", show_alert: true)
          end
          unless user
            return Telegram::Api.answer_callback(cb_id, t.(:no_linked_account), show_alert: false)
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
            buttons << [{ text: t.(:save), callback_data: "profile:sports:save" }, { text: t.(:back), callback_data: "profile:sports:cancel" }]

            text = t.(:editing_field, field: t.(:field_sports), current: (selections.any? ? selections.join(", ") : "—"), hint: t.(:sports_editing_prompt))

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
              [{ text: t.(:yes_label), callback_data: "profile:field:notify:yes" }],
              [{ text: t.(:no_label),  callback_data: "profile:field:notify:no"  }],
              [{ text: t.(:back),      callback_data: "profile:field:cancel" }]
            ]
            text = t.(:editing_field, field: t.(:field_notify), current: current, hint: "")

            if message_id
              Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons) rescue nil
              Telegram::Api.answer_callback(cb_id) rescue nil
            else
              Telegram::Api.send_with_buttons(chat_id, text, buttons) rescue nil
              Telegram::Api.answer_callback(cb_id) rescue nil
            end

            return
          end

          # handle coach as inline checkbox (Yes/No)
          if field.to_s == "coach"
            conv = { "flow" => "profile_field", "field" => "coach", "created_at" => Time.current }
            begin
              Rails.cache.write("tg:conv:#{chat_id}", conv, expires_in: 10.minutes)
            rescue => e
              Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] start_edit_field: cache write failed for chat=#{chat_id}: #{e.class}: #{e.message}"
            end

            current = presenter.current_value_for("coach")
            buttons = [
              [{ text: t.(:yes_label), callback_data: "profile:field:coach:yes" }],
              [{ text: t.(:no_label),  callback_data: "profile:field:coach:no"  }],
              [{ text: t.(:back),      callback_data: "profile:field:cancel" }]
            ]
            text = t.(:editing_field, field: t.(:field_coach), current: current, hint: "")

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
          text = t.(:editing_field, field: field, current: current, hint: t.(:send_new_value))

          if message_id
            buttons = [[{ text: t.(:back), callback_data: "profile:field:cancel" }]]
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons) rescue nil
            Telegram::Api.answer_callback(cb_id) rescue nil
          else
            Telegram::Api.send_simple(chat_id, text) rescue nil
            Telegram::Api.answer_callback(cb_id) rescue nil
          end
        end

        def process_profile_field_reply(message)
          chat = message["chat"] || {}
          chat_id = (chat["id"] || message.dig("from", "id")).to_s
          text = message["text"].to_s.strip
          return unless text.present?

          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          begin
            conv = Rails.cache.read("tg:conv:#{chat_id}") || {}
          rescue => e
            Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] process_profile_field_reply: cache read failed for chat=#{chat_id}: #{e.class}: #{e.message}"
            conv = {}
          end
          field = conv && conv["field"]
          unless field
            return Telegram::Api.send_simple(chat_id, t.(:no_pending_edit))
          end

          if text.downcase == "back"
            begin
              Rails.cache.delete("tg:conv:#{chat_id}")
            rescue => e
              Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] process_profile_field_reply: cache delete failed for chat=#{chat_id}: #{e.class}: #{e.message}"
            end
            return Telegram::Api.send_simple(chat_id, t.(:edit_cancelled))
          end

          user = User.find_by(telegram_chat_id: chat_id.to_s) rescue nil
          return Telegram::Api.send_simple(chat_id, t.(:no_linked_account)) unless user

          case field
          when "email"
            if text.present?
              taken = User.where('LOWER("users"."email") = LOWER(?)', text)
                          .where.not(id: user.id)
                          .exists?
              if taken
                return Telegram::Api.send_simple(chat_id, t.(:email_already_taken))
              end
            end

            user.email = text if user.respond_to?(:email=)
            user.timezone = nil if user.respond_to?(:timezone=)
          when "city"
            translit_input = translit_str(text)
            user.city_name = translit_input if user.respond_to?(:city_name=)
            user.location = text if user.respond_to?(:location=)
            if user.respond_to?(:timezone=)
              user.timezone = nil
            end
          when "notify"
            val = (text.downcase == "yes" || text == "1" || text.downcase == "true" || text.downcase == "да")
            user.notify_nearby = val if user.respond_to?(:notify_nearby=)
            user.notify = val if user.respond_to?(:notify=)
          else
            return Telegram::Api.send_simple(chat_id, t.(:unknown_field))
          end

          begin
            if user.save
              begin
                Rails.cache.delete("tg:conv:#{chat_id}")
              rescue => e
                Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] process_profile_field_reply: cache delete failed for chat=#{chat_id}: #{e.class}: #{e.message}"
              end
              ResolveUserCityJob.perform_later(user.id, text) if field == "city" && text.present?
              Telegram::Api.send_simple(chat_id, t.(:field_updated))
              Telegram::Handlers::ProfileHandler.show_profile(chat_id) rescue nil
            else
              if user.errors.any?
                msgs = user.errors.full_messages.join(", ")
                Telegram::Api.send_simple(chat_id, t.(:field_update_failed, errors: msgs))
              else
                Telegram::Api.send_simple(chat_id, t.(:validation_failed))
              end
            end
          rescue ActiveRecord::RecordNotUnique => e
            Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] DB unique constraint failed: #{e.class}: #{e.message}"
            Telegram::Api.send_simple(chat_id, t.(:unique_constraint))
          rescue => e
            Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] profile field save exception user_id=#{user&.id} #{e.class}: #{e.message}"
            Telegram::Api.send_simple(chat_id, t.(:field_update_failed, errors: e.message))
          end
        end

        def process_notify_callback(chat_id, action, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          begin
            user = User.find_by(telegram_chat_id: chat_id.to_s)
          rescue => e
            Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] process_notify_callback: DB error for chat=#{chat_id}: #{e.class}: #{e.message}"
            return Telegram::Api.answer_callback(cb_id, "Internal error", show_alert: true)
          end
          unless user
            return Telegram::Api.answer_callback(cb_id, t.(:no_linked_account), show_alert: false)
          end

          if action == "cancel"
            begin
              Rails.cache.delete("tg:conv:#{chat_id}")
            rescue => e
              Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] process_notify_callback: cache delete failed for chat=#{chat_id}: #{e.class}: #{e.message}"
            end
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, t.(:edit_cancelled), [[{ text: t.(:edit_profile), callback_data: "profile:edit" }]]) rescue nil
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
            Telegram::Flows::ProfileFlow.start_edit_profile(chat_id, message_id: message_id)
            Telegram::Api.answer_callback(cb_id, "#{t.(:field_notify)}: #{val ? t.(:yes_label) : t.(:no_label)}") rescue nil
          else
            Telegram::Api.answer_callback(cb_id, "Failed to save", show_alert: true) rescue nil
          end
        end

        def process_coach_callback(chat_id, action, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          begin
            user = User.find_by(telegram_chat_id: chat_id.to_s)
          rescue => e
            Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] process_coach_callback: DB error for chat=#{chat_id}: #{e.class}: #{e.message}"
            return Telegram::Api.answer_callback(cb_id, "Internal error", show_alert: true)
          end
          unless user
            return Telegram::Api.answer_callback(cb_id, t.(:no_linked_account), show_alert: false)
          end

          if action == "cancel"
            begin
              Rails.cache.delete("tg:conv:#{chat_id}")
            rescue => e
              Rails.logger.error "[Telegram::Flows::Profile::FieldFlow] process_coach_callback: cache delete failed for chat=#{chat_id}: #{e.class}: #{e.message}"
            end
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, t.(:edit_cancelled), [[{ text: t.(:edit_profile), callback_data: "profile:edit" }]]) rescue nil
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
            Telegram::Flows::ProfileFlow.start_edit_profile(chat_id, message_id: message_id)
            Telegram::Api.answer_callback(cb_id, "#{t.(:field_coach)}: #{val ? t.(:yes_label) : t.(:no_label)}") rescue nil
          else
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
