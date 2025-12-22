module Telegram
  class MessageHandler
    # handle incoming Telegram "message" updates (force-reply flows etc.)
    def self.handle(message)
      message = message.to_h if message.respond_to?(:to_h)
      chat_id = message.dig("chat", "id") || message.dig("from", "id")
      return unless chat_id

      key = "tg:conv:#{chat_id}"
      conv = Rails.cache.read(key) || {}

      if conv["step"] == "ask_singles_hours"
        text = message["text"].to_s.strip
        if text.present?
          if text.downcase == "skip"
            Api.send_simple(chat_id, "Skipped.")
          elsif text.match?(/\A\d+(\.\d+)?\z/)
            # TODO: persist value into player statistics using conv["game_id"]
            Api.send_simple(chat_id, "Got #{text}. Thank you.")
          else
            Api.send_force_reply(chat_id, "Please reply with a number like 1.5 or type 'skip'.")
            return
          end
        else
          Api.send_force_reply(chat_id, "Please reply with a number like 1.5 or type 'skip'.")
          return
        end

        Rails.cache.delete(key)
        return
      end

      Rails.logger.info("[Telegram::MessageHandler] Unhandled message from #{chat_id}: #{message.keys}")
    rescue => e
      Rails.logger.error("[Telegram::MessageHandler] #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}")
    end
  end
end
