module Telegram
  module Handlers
    module ReplyHelpers
      def send_or_edit_with_buttons(chat_id, text, buttons, message_id: nil)
        if message_id
          Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons)
        else
          Telegram::Api.send_with_buttons(chat_id, text, buttons)
        end
      end

      def send_or_edit_text(chat_id, text, message_id: nil)
        if message_id
          Telegram::Api.edit_message_text(chat_id, message_id, text)
        else
          Telegram::Api.send_simple(chat_id, text)
        end
      end
    end
  end
end
