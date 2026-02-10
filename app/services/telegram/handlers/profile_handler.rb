module Telegram
  module Handlers
    class ProfileHandler
      class << self
        include Telegram::Handlers::ReplyHelpers

        def menu(chat_id, message_id: nil)
          buttons = [
            [{ text: "Edit profile", callback_data: "profile:edit" }],
            [{ text: "Main menu",  callback_data: "menu:main" }]
          ]

          send_or_edit_with_buttons(chat_id, "Profile:", buttons, message_id: message_id)
        end

        def show_profile(chat_id, message_id: nil)
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          return Telegram::Api.send_simple(chat_id, "No linked account. Send /start first.") unless user

          presenter = Telegram::Presenters::ProfilePresenter.new(user)

          lines = []
          lines << "*Profile:*"
          lines << "Email: #{presenter.email_label}"
          lines << "Sports: #{presenter.sports_label}"
          lines << "City: #{presenter.city_label}"
          lines << "Coach: #{presenter.coach_label}"
          lines << "Notify nearby searches: #{presenter.notify_label}"
          text = lines.join("\n")

          buttons = [
            [{ text: "Edit profile", callback_data: "profile:edit" }],
            [{ text: "Main menu",  callback_data: "menu:main" }]
          ]

          send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
        end
      end
    end
  end
end
