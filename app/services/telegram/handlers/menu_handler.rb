module Telegram
  module Handlers
    class MenuHandler
      class << self
        def menu(chat_id, message_id: nil)
          text = "Main menu:"

          buttons = [
            [{ text: "Courts",  callback_data: "menu:courts:page:1" }],
            [{ text: "Games",   callback_data: "menu:games:page:1" }],
            # [{ text: "Search",  callback_data: "menu:search" }],
            [{ text: "Profile", callback_data: "profile:show" }]
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
