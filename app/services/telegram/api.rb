require "net/http"
require "uri"
require "json"

module Telegram
  module Api
    TOKEN = ENV["TELEGRAM_BOT_TOKEN"].to_s
    API_BASE = "https://api.telegram.org/bot#{TOKEN}"

    def self.post_json(path, payload)
      return {} if TOKEN.blank?
      uri = URI("#{API_BASE}/#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      req = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
      req.body = payload.to_json
      res = http.request(req)
      JSON.parse(res.body) rescue {}
    rescue => e
      Rails.logger.error "[Telegram::Api] #{e.class} #{e.message}"
      {}
    end

    def self.send_with_buttons(chat_id, text, buttons = [], parse_mode: "Markdown")
      kb = { inline_keyboard: [ buttons.map { |b|
        if b[:url]
          { text: b[:text], url: b[:url] }
        else
          { text: b[:text], callback_data: b[:callback_data] }
        end
      } ] }
      post_json("sendMessage", chat_id: chat_id.to_s, text: text.to_s, reply_markup: kb, parse_mode: parse_mode)
    end

    def self.send_force_reply(chat_id, text, parse_mode: "Markdown")
      kb = { force_reply: true }
      post_json("sendMessage", chat_id: chat_id.to_s, text: text.to_s, reply_markup: kb, parse_mode: parse_mode)
    end

    def self.answer_callback(callback_query_id, text = nil, show_alert: false)
      post_json("answerCallbackQuery", callback_query_id: callback_query_id, text: text, show_alert: show_alert)
    end

    def self.send_simple(chat_id, text, parse_mode: "Markdown")
      # use existing Telegram::Notifier.send_message to keep current behavior if desired
      Telegram::Notifier.send_message(chat_id, text, parse_mode: parse_mode)
    end
  end
end
