module Telegram
  module Processors
    class ReplyProcessor
      class << self
        # return true if message was handled as a reply-to-prompt
        def process(message)
          chat = message["chat"] || {}
          chat_id = (chat["id"] || message.dig("from","id")).to_s
          text = message["text"].to_s.strip
          return false unless chat_id.present? && text.present?

          conv = Telegram::Helpers::Conversation.get(chat_id) rescue {}
          flow = conv && conv["flow"]

          case flow
          when "profile_field"
            Telegram::Flows::Profile::FieldFlow.process_profile_field_reply(message)
            return true
          when "profile_sports"
            # sports editing is interactive via buttons; guide the user
            Telegram::Api.send_simple(chat_id, "Please use the buttons to edit your sports.") rescue nil
            return true
          when "search_name"
            Telegram::Handlers::SearchHandler.search_by_name(chat_id, text, 1) rescue nil
            return true
          else
            return false
          end
        rescue => e
          Rails.logger.error "[Telegram::Processors::ReplyProcessor] process error: #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
          false
        end
      end
    end
  end
end
