module Telegram
  module Helpers
    # Centralised user lookup by telegram chat_id.
    # Replaces the ~12 occurrences of:
    #   User.find_by(telegram_chat_id: chat_id.to_s) rescue nil
    module UserLookup
      def self.find_user(chat_id)
        User.find_by(telegram_chat_id: chat_id.to_s)
      rescue => e
        Rails.logger.error "[Telegram::Helpers::UserLookup] #{e.class}: #{e.message}"
        nil
      end

      # Find user and return their locale (shortcut for i18n)
      def self.locale_for(chat_id)
        user = find_user(chat_id)
        Telegram::I18n.locale_for(user)
      end

      # Returns the best display name for a user: @telegram_username > @username > name > fallback
      def self.display_name(user, fallback: "User")
        return fallback unless user

        if user.respond_to?(:telegram_username) && user.telegram_username.to_s.strip.present?
          "@#{user.telegram_username.to_s.strip.delete_prefix('@')}"
        elsif user.respond_to?(:username) && user.username.to_s.strip.present?
          "@#{user.username.to_s.strip.delete_prefix('@')}"
        else
          user.name.to_s.strip.presence || fallback
        end
      end
    end
  end
end
