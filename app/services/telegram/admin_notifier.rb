require "net/http"
require "uri"

module Telegram
  class AdminNotifier
    def self.notify_court_pending(court, base_url:, action:)
      token = ENV["TELEGRAM_BOT_TOKEN"].to_s
      return if token.empty?

      # prefer explicit ENV, otherwise take first admin user with telegram_chat_id from DB
      chat_id = ENV["TELEGRAM_ADMIN_CHAT_ID"].presence
      unless chat_id
        admin_user = User.where(admin: true).where.not(telegram_chat_id: nil).order(:created_at).first
        chat_id = admin_user&.telegram_chat_id
      end
      chat_id = chat_id.to_s.presence
      return if chat_id.blank?

      host = base_url.to_s.presence || ENV["APP_HOST"].to_s.presence
      return if host.blank?

      url = "#{host}/courts/#{court.id}"
      text = "Court pending approval (#{action}): #{court.name} — #{url}"

      uri = URI("https://api.telegram.org/bot#{token}/sendMessage")
      Net::HTTP.post_form(uri, { "chat_id" => chat_id, "text" => text })
    end
  end
end
