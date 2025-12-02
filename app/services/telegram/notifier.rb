require "net/http"
require "uri"
require "json"

module Telegram
  class Notifier
    TOKEN = ENV["TELEGRAM_BOT_TOKEN"].to_s

    def self.send_message(chat_id, text, parse_mode: "Markdown")
      return false if TOKEN.empty? || chat_id.blank?

      uri = URI("https://api.telegram.org/bot#{TOKEN}/sendMessage")
      res = Net::HTTP.post_form(uri, { "chat_id" => chat_id.to_s, "text" => text.to_s, "parse_mode" => parse_mode })
      body = JSON.parse(res.body) rescue {}
      body["ok"] == true
    end
  end
end
