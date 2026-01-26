module Telegram
  module Helpers
    class Conversation
      TTL = 2.hours
      KEY_PREFIX = "tg:conv:"

      class << self
        def key(chat_id)
          "#{KEY_PREFIX}#{chat_id}"
        end

        # Backward-compatible alias for callers that use `.set`
        def set(chat_id, attrs = {})
          start(chat_id, attrs)
        end

        # start or update conversation state, returns stored state or false on failure
        def start(chat_id, attrs = {})
          state = attrs.merge("created_at" => Time.current)
          Rails.cache.write(key(chat_id), state, expires_in: TTL)
          state
        rescue => e
          Rails.logger.error "[Telegram::Helpers::Conversation] start error: #{e.class}: #{e.message}"
          false
        end

        # return stored state hash or empty hash
        def get(chat_id)
          Rails.cache.read(key(chat_id)) || {}
        rescue => e
          Rails.logger.error "[Telegram::Helpers::Conversation] get error: #{e.class}: #{e.message}"
          {}
        end

        def finish(chat_id)
          Rails.cache.delete(key(chat_id)) rescue nil
        end
      end
    end
  end
end
