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

      # Returns the best display name for a user. In Telegram an @handle is a live
      # mention, in an email it says nothing — there a name and an address do:
      #   telegram: @telegram_username > @username > name > email > fallback
      #   email:    name > email > @telegram_username > @username > fallback
      def self.display_name(user, fallback: "User", channel: :telegram)
        return fallback unless user

        parts =
          if channel.to_s == "email"
            [ real_name(user), contact_email(user), telegram_handle(user) ]
          else
            [ telegram_handle(user), real_name(user), contact_email(user) ]
          end

        parts.compact.first || fallback
      end

      def self.telegram_handle(user)
        handle = user.telegram_username if user.respond_to?(:telegram_username)
        handle = user.username if handle.to_s.strip.blank? && user.respond_to?(:username)

        "@#{handle.to_s.strip.delete_prefix("@")}" if handle.to_s.strip.present?
      end

      def self.real_name(user)
        user.name.to_s.strip.presence if user.respond_to?(:name)
      end

      # Почта, выписанная боту при регистрации, человеку ничего не говорит.
      def self.contact_email(user)
        return nil if user.respond_to?(:telegram_generated_email?) && user.telegram_generated_email?

        user.email.to_s.strip.presence if user.respond_to?(:email)
      end
    end
  end
end
