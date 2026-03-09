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

        # Merge attrs into existing state (preserves current keys)
        def update(chat_id, attrs = {})
          state = get(chat_id).merge(attrs)
          Rails.cache.write(key(chat_id), state, expires_in: TTL)
          state
        rescue => e
          Rails.logger.error "[Telegram::Helpers::Conversation] update error: #{e.class}: #{e.message}"
          false
        end

        # return stored state hash or empty hash
        def get(chat_id)
          Rails.cache.read(key(chat_id)) || {}
        rescue => e
          Rails.logger.error "[Telegram::Helpers::Conversation] get error: #{e.class}: #{e.message}"
          {}
        end

        # Read state, then delete it; returns the state (so callers can persist it)
        def finish(chat_id)
          state = get(chat_id)
          Rails.cache.delete(key(chat_id)) rescue nil
          state
        end

        # --- convenience helpers used by survey / other handlers ---

        def set_step(chat_id, step)
          update(chat_id, "step" => step)
        end

        def set_city(chat_id, city)
          update(chat_id, "city" => city)
        end

        def toggle_sport(chat_id, sport)
          state = get(chat_id)
          selected = (state["selected_sports"] || []).map(&:to_s)
          selected.include?(sport) ? selected.delete(sport) : selected << sport
          update(chat_id, "selected_sports" => selected)
        end

        def set_skill(chat_id, sport, level)
          state = get(chat_id)
          skills = (state["skills"] || {}).merge(sport => level)
          update(chat_id, "skills" => skills)
        end

        def set_notifications(chat_id, value)
          update(chat_id, "notifications" => value)
        end
      end
    end
  end
end
