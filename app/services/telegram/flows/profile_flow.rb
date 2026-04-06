module Telegram
  module Flows
    class ProfileFlow
      class << self
        include Telegram::Handlers::ReplyHelpers

        def handle_callback(callback)
          cb = Telegram::Helpers::CallbackData.parse(callback)
          Rails.logger.info "[Telegram::Flows::ProfileFlow] handle_callback data=#{cb.data.inspect} chat_id=#{cb.chat_id} cb_id=#{cb.cb_id}"
          locale = Telegram::Helpers::UserLookup.locale_for(cb.chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          poller = Telegram::Poller.new

          case cb.data
          when /\Aprofile:field:coach:(yes|no|cancel)\z/
            action = Regexp.last_match(1)
            Profile::FieldFlow.process_coach_callback(cb.chat_id, action, cb_id: cb.cb_id, message_id: cb.message_id)
            nil
          when /\Aprofile:field:notify:(yes|no|cancel)\z/
            action = Regexp.last_match(1)
            Profile::FieldFlow.process_notify_callback(cb.chat_id, action, cb_id: cb.cb_id, message_id: cb.message_id)
            nil
          when /\Aprofile:sports:(toggle|save|cancel|level|level_set|save_levels)(?::(.+))?\z/
            action = Regexp.last_match(1)
            arg = Regexp.last_match(2)
            Profile::SportsFlow.process_sports_callback(cb.chat_id, action, (arg && CGI.unescape(arg)), cb_id: cb.cb_id, message_id: cb.message_id)
            nil
          when /\Aprofile:favorite_courts:(toggle|page|save|cancel)(?::(.+))?\z/
            action = Regexp.last_match(1)
            arg = Regexp.last_match(2)
            Profile::FavoriteCourtsFlow.process_favorite_courts_callback(cb.chat_id, action, arg, cb_id: cb.cb_id, message_id: cb.message_id)
            nil
          when /\Aprofile:lang:(ru|en)\z/
            new_locale = Regexp.last_match(1)
            process_language_change(cb.chat_id, new_locale, cb_id: cb.cb_id, message_id: cb.message_id)
            nil
          when /\Aprofile:show\z/
            Telegram::Handlers::ProfileHandler.show_profile(cb.chat_id, message_id: cb.message_id)
            poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil
            nil
          when /\Aprofile:edit\z/
            start_edit_profile(cb.chat_id, cb_id: cb.cb_id, message_id: cb.message_id)
            nil
          when /\Aprofile:field:(\w+)\z/
            field = Regexp.last_match(1)

            if field == "cancel"
              Telegram::Helpers::Conversation.finish(cb.chat_id) rescue nil
              Telegram::Api.edit_message_with_buttons(
                cb.chat_id,
                cb.message_id,
                t.(:edit_cancelled),
                [ [ { text: t.(:edit_profile), callback_data: "profile:edit" } ] ]
              ) rescue nil
              Telegram::Api.answer_callback(cb.cb_id) rescue nil
              return
            end

            if field == "language"
              show_language_picker(cb.chat_id, cb_id: cb.cb_id, message_id: cb.message_id)
              return
            end

            Profile::FieldFlow.start_edit_field(cb.chat_id, field, cb_id: cb.cb_id, message_id: cb.message_id)
            nil
          else
            poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: t.(:unknown_action), show_alert: false }) rescue nil
            nil
          end
        rescue => e
          Rails.logger.error "[Telegram::Flows::ProfileFlow] callback error: #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
        end

        def start_edit_profile(chat_id, cb_id: nil, message_id: nil)
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          locale = Telegram::I18n.locale_for(user)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          unless user
            return Telegram::Api.answer_callback(cb_id, t.(:no_linked_account), show_alert: false)
          end

          presenter = Telegram::Presenters::ProfilePresenter.new(user)
          lang_label = locale == "ru" ? "Русский" : "English"

          text = [
            t.(:edit_profile_title),
            t.(:email_label, value: presenter.email_label),
            t.(:sports_label, value: presenter.sports_label),
            t.(:city_label, value: presenter.city_label),
            t.(:favorite_courts_label, value: presenter.favorite_courts_label),
            t.(:coach_label, value: presenter.coach_label),
            (t.(:court_note_label, value: presenter.court_note_label) if user.coach? || user.court_preferences_note.present?),
            t.(:notify_label, value: presenter.notify_label),
            t.(:language_label, value: lang_label),
            "",
            t.(:select_field_to_edit)
          ].compact.join("\n")

          buttons = [
            [ { text: t.(:field_email),    callback_data: "profile:field:email" } ],
            [ { text: t.(:field_sports),   callback_data: "profile:field:sports" } ],
            [ { text: t.(:field_city),     callback_data: "profile:field:city" } ],
            [ { text: t.(:field_favorite_courts), callback_data: "profile:field:favorite_courts" } ],
            [ { text: t.(:field_coach),    callback_data: "profile:field:coach" } ],
            [ { text: t.(:field_notify),   callback_data: "profile:field:notify" } ],
            [ { text: t.(:field_language), callback_data: "profile:field:language" } ],
            [ { text: t.(:back),           callback_data: "profile:show" } ]
          ]
          buttons.insert(4, [ { text: t.(:field_court_note), callback_data: "profile:field:court_note" } ]) if user.coach?

          send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
          Telegram::Api.answer_callback(cb_id) rescue nil
        end

        def process_profile_field_reply(message)
          Profile::FieldFlow.process_profile_field_reply(message)
        end

        private

        def show_language_picker(chat_id, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          text = t.(:select_language)
          buttons = [
            [ { text: "🇷🇺 #{t.(:language_russian)}", callback_data: "profile:lang:ru" } ],
            [ { text: "🇬🇧 #{t.(:language_english)}", callback_data: "profile:lang:en" } ],
            [ { text: t.(:back), callback_data: "profile:edit" } ]
          ]

          if message_id
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons) rescue nil
          else
            Telegram::Api.send_with_buttons(chat_id, text, buttons) rescue nil
          end
          Telegram::Api.answer_callback(cb_id) rescue nil
        end

        def process_language_change(chat_id, new_locale, cb_id: nil, message_id: nil)
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          unless user
            Telegram::Api.answer_callback(cb_id, "No linked account", show_alert: false) rescue nil
            return
          end

          user.update_column(:telegram_locale, new_locale)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: new_locale, **args) }

          Telegram::Api.answer_callback(cb_id, t.(:language_changed)) rescue nil
          start_edit_profile(chat_id, message_id: message_id)
        end
      end
    end
  end
end
