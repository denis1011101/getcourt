module Telegram
  module Processors
    class ReplyProcessor
      class << self
        def process(message)
          chat = message["chat"] || {}
          chat_id = (chat["id"] || message.dig("from","id")).to_s

          # Handle location messages for court creation
          if message["location"]
            conv = Telegram::Helpers::Conversation.get(chat_id) rescue {}
            if conv["flow"] == "create_court"
              return Telegram::Flows::CourtCreateFlow.process_location(message)
            end
            return false
          end

          text = message["text"].to_s.strip
          return false unless chat_id.present? && text.present?

          conv = Telegram::Helpers::Conversation.get(chat_id) rescue {}
          flow = conv && conv["flow"]

          case flow
          when "profile_field"
            Telegram::Flows::Profile::FieldFlow.process_profile_field_reply(message)
            return true
          when "profile_sports"
            Telegram::Api.send_simple(chat_id, "Please use the buttons to edit your sports.") rescue nil
            return true
          when "search_name"
            Telegram::Handlers::SearchHandler.search_by_name(chat_id, text, 1) rescue nil
            return true
          when "game_stats_input"
            return Telegram::Flows::StatsFlow.process_text(message)
          when "create_game"
            return Telegram::Flows::Games::Manage::CreateFlow.process_text(message)
          when "create_court"
            return Telegram::Flows::CourtCreateFlow.process_text(message)
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
