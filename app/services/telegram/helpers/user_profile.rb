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

        # Map conversation state to real user attributes and assign (does not save).
        def apply_to_user(user, state)
          attrs = {}

          # language → telegram_locale
          if state["language"].present?
            attrs[:telegram_locale] = state["language"]
          end

          # city → city_name
          if state["city"].present?
            attrs[:city_name] = state["city"]
          end

          # selected_sports → preferred_sports (virtual :json attribute, assign array directly)
          if state["selected_sports"].is_a?(Array) && state["selected_sports"].any?
            attrs[:preferred_sports] = state["selected_sports"]
          end

          # skills → skill_levels (json column)
          if state["skills"].is_a?(Hash) && state["skills"].any?
            attrs[:skill_levels] = state["skills"]
          end

          # coach → coach (nullable boolean: true/false/nil)
          if state.key?("coach")
            attrs[:coach] = state["coach"] # nil means skipped
          end

          # notifications → notify_nearby
          if state.key?("notifications") && !state["notifications"].nil?
            attrs[:notify_nearby] = !!state["notifications"]
          end

          user.assign_attributes(attrs) if attrs.any?
        end
      end
    end
  end
end
