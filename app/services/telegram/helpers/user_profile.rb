module Telegram
  module Helpers
    class UserProfile
      class << self
        # Persist conversation state into the given user record.
        # If finish: true will clear the conversation (Conversation.finish), otherwise reads current state.
        # Returns the state on success, false on failure.
        def persist_from_conversation(chat_id, user, finish: true)
          state = finish ? Conversation.finish(chat_id) : Conversation.get(chat_id)
          return false if state.blank? || user.nil?
          apply_to_user(user, state)
          user.save ? state : false
        rescue => e
          Rails.logger.error "[Telegram::Helpers::UserProfile] persist error: #{e.class} #{e.message}"
          false
        end

        # Map conversation state to user attributes and assign (does not save).
        def apply_to_user(user, state)
          attrs = {}

          attrs[:telegram_city] = state["city"] if state["city"].present?

          if state["selected_sports"].is_a?(Array) && state["selected_sports"].any?
            if user_has_column?(user, :telegram_sports)
              # Try to assign array directly; DB type may be array/json/text
              attrs[:telegram_sports] = state["selected_sports"]
            else
              attrs[:telegram_sports] = state["selected_sports"].join(",")
            end
          end

          if state["skills"].is_a?(Hash) && state["skills"].any?
            if user_has_column?(user, :telegram_skills)
              col = safe_column(user, "telegram_skills")
              if col && [ :json, :jsonb ].include?(col.type)
                attrs[:telegram_skills] = state["skills"]
              else
                attrs[:telegram_skills] = state["skills"].to_json
              end
            else
              attrs[:telegram_skills] = state["skills"].to_json
            end
          end

          if state.key?("notifications")
            if user_has_column?(user, :telegram_notifications)
              attrs[:telegram_notifications] = !!state["notifications"]
            else
              # fallback: try generic notifications flag
              user.respond_to?(:notifications=) ? attrs[:notifications] = !!state["notifications"] : nil
            end
          end

          user.assign_attributes(attrs) if attrs.any?
        end

        private

        def user_has_column?(user, col)
          user.class.respond_to?(:column_names) && user.class.column_names.include?(col.to_s)
        end

        def safe_column(user, name)
          return nil unless user.class.respond_to?(:columns_hash)
          user.class.columns_hash[name]
        rescue
          nil
        end
      end
    end
  end
end
