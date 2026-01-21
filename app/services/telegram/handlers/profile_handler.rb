module Telegram
  module Handlers
    class ProfileHandler
      class << self
        def menu(chat_id, message_id: nil)
          buttons = [
            [{ text: "Edit profile", callback_data: "profile:edit" }],
            [{ text: "Main menu",  callback_data: "menu:main" }]
          ]

          if message_id
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, "Profile:", buttons)
          else
            Telegram::Api.send_with_buttons(chat_id, "Profile:", buttons)
          end
        end

        def show_profile(chat_id, message_id: nil)
          user = User.find_by(telegram_chat_id: chat_id.to_s) rescue nil
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

          if message_id
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons)
          else
            Telegram::Api.send_with_buttons(chat_id, text, buttons)
          end
        end
      end
    end
  end
end
