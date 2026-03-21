module Telegram
  module Handlers
    class AiAssistantHandler
      class << self
        include Telegram::Handlers::ReplyHelpers

        def show(chat_id, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          Telegram::Helpers::Conversation.start(chat_id, {
            "flow" => "ai_assistant",
            "message_id" => message_id
          })

          buttons = [
            [ { text: t.(:ai_snippet_find_opponent), callback_data: "ai:snippet:find_opponent" } ],
            [ { text: t.(:ai_snippet_find_court), callback_data: "ai:snippet:find_court" } ],
            [ { text: t.(:ai_snippet_find_coach), callback_data: "ai:snippet:find_coach" } ],
            [ { text: t.(:ai_back_to_menu), callback_data: "ai:back" } ]
          ]

          send_or_edit_with_buttons(chat_id, t.(:ai_assistant_welcome), buttons, message_id: message_id)
        end
      end
    end
  end
end
