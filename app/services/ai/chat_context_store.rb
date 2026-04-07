module Ai
  class ChatContextStore
    TTL = 10.minutes
    HISTORY_LIMIT = 6

    class << self
      def fetch(channel:, key:)
        Rails.cache.read(cache_key(channel:, key:)) || []
      end

      def append(channel:, key:, user_message:, assistant_message:)
        history = fetch(channel:, key:)
        updated_history = history.last(HISTORY_LIMIT - 2) + [
          { role: "user", content: user_message.to_s },
          { role: "assistant", content: assistant_message.to_s }
        ]

        Rails.cache.write(cache_key(channel:, key:), updated_history, expires_in: TTL)
        updated_history
      end

      def clear(channel:, key:)
        Rails.cache.delete(cache_key(channel:, key:))
      end

      private

      def cache_key(channel:, key:)
        "ai_chat/history/#{channel}/#{key}"
      end
    end
  end
end
