module Telegram
  module Handlers
    class MenuHandler
      class << self
        include Telegram::Handlers::ReplyHelpers

        def menu(chat_id, message_id: nil)
          text = "Main menu:"

          buttons = [
            [{ text: "Courts",  callback_data: "menu:courts:page:1" }],
            [{ text: "Games",   callback_data: "menu:games:page:1" }],
            # [{ text: "Search",  callback_data: "menu:search" }],
            [{ text: "Profile", callback_data: "profile:show" }]
          ]

          send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
        end
      end
    end
  end
end
