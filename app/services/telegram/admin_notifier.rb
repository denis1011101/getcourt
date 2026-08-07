module Telegram
  class AdminNotifier
    def self.notify_partnership(text)
      send_message(:admin_partnership, text: text)
    end

    def self.notify_court_pending(court, base_url:, action:)
      host = base_url.to_s.presence || ENV["APP_HOST"].to_s.presence
      return if host.blank?

      send_message(
        :admin_court_pending,
        action: action,
        name: court.name,
        url: "#{host}/courts/#{court.id}"
      )
    end

    def self.notify_court_suggestion(suggestion, base_url:)
      host = base_url.to_s.presence || ENV["APP_HOST"].to_s.presence
      return if host.blank?

      send_message(
        :admin_court_suggestion,
        name: suggestion.court.name,
        url: "#{host}/court_suggestions/#{suggestion.id}"
      )
    end

    def self.send_message(key, **args)
      recipient = admin_recipient
      return unless recipient

      text = Telegram::I18n.t(key, locale: recipient[:locale], **args)
      Telegram::Api.send_simple(recipient[:chat_id], text, parse_mode: nil)
    rescue StandardError => e
      Rails.logger.error("[Telegram::AdminNotifier] #{e.class}: #{e.message}")
      nil
    end

    def self.admin_recipient
      configured_chat_id = ENV["TELEGRAM_ADMIN_CHAT_ID"].to_s.presence
      if configured_chat_id
        return { chat_id: configured_chat_id, locale: Telegram::I18n::DEFAULT_LOCALE }
      end

      user = User.where(admin: true).where.not(telegram_chat_id: nil).order(:created_at).first
      return unless user

      { chat_id: user.telegram_chat_id, locale: Telegram::I18n.locale_for(user) }
    end

    private_class_method :send_message, :admin_recipient
  end
end
