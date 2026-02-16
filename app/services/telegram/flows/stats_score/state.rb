module Telegram
  module Flows
    module StatsScore
      module State
        module_function

        def get(chat_id)
          conv = Telegram::Helpers::Conversation.get(chat_id) rescue {}
          conv.is_a?(Hash) ? conv : {}
        end

        def set(chat_id, payload)
          Telegram::Helpers::Conversation.set(chat_id, payload) rescue nil
        end

        def fields_and_page_from(conv)
          fields = (conv.is_a?(Hash) && conv["fields"].is_a?(Hash)) ? conv["fields"] : {}
          page = (conv.is_a?(Hash) && conv["page"].to_i > 0) ? conv["page"].to_i : 1
          [ fields, page ]
        end
      end
    end
  end
end
