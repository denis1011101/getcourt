module Telegram
  module Handlers
    class ProfileHandler
      class << self
        include Telegram::Handlers::ReplyHelpers

        def menu(chat_id, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          buttons = [
            [ { text: t.(:edit_profile), callback_data: "profile:edit" } ],
            [ { text: t.(:main_menu_btn), callback_data: "menu:main" } ]
          ]
          send_or_edit_with_buttons(chat_id, "#{t.(:profile)}:", buttons, message_id: message_id)
        end

        def show_profile(chat_id, message_id: nil)
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          locale = Telegram::I18n.locale_for(user)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          return Telegram::Api.send_simple(chat_id, t.(:no_linked_account)) unless user

          presenter = Telegram::Presenters::ProfilePresenter.new(user)
          lang_label = locale == "ru" ? "Русский" : "English"

          lines = []
          lines << t.(:profile_title)
          lines << t.(:email_label, value: presenter.email_label)
          lines << t.(:sports_label, value: presenter.sports_label)
          lines << t.(:city_label, value: presenter.city_label)
          lines << t.(:coach_label, value: presenter.coach_label)
          lines << t.(:notify_label, value: presenter.notify_label)
          lines << t.(:language_label, value: lang_label)
          lines << t.(:about_me_label, value: presenter.about_me_label)
          text = lines.join("\n")

          buttons = [
            [ { text: t.(:edit_profile), callback_data: "profile:edit" } ],
            [ { text: t.(:main_menu_btn), callback_data: "menu:main" } ]
          ]

          send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
        end
      end
    end
  end
end
