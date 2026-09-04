require "net/http"
require "uri"
require "json"

module Telegram
  class Notifier
    TOKEN = ENV["TELEGRAM_BOT_TOKEN"].to_s

    # silent: письмо приходит без звука и вибрации — для того, что бот шлёт по
    # расписанию среди ночи и что человеку достаточно прочитать утром.
    def self.send_message(chat_id, text, parse_mode: "Markdown", link_preview: false, silent: false)
      return false if TOKEN.empty? || chat_id.blank?

      uri = URI("https://api.telegram.org/bot#{TOKEN}/sendMessage")
      payload = { "chat_id" => chat_id.to_s, "text" => text.to_s }
      payload["parse_mode"] = parse_mode if parse_mode.present?
      payload["link_preview_options"] = Telegram::Api::LINK_PREVIEW_DISABLED unless link_preview
      payload["disable_notification"] = "true" if silent
      res = Net::HTTP.post_form(uri, payload)
      body = JSON.parse(res.body) rescue {}
      body["ok"] == true
    end
  end
end
