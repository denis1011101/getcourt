require "net/http"
require "uri"
require "json"

module Telegram
  module Api
    TOKEN = ENV["TELEGRAM_BOT_TOKEN"].to_s

    def self.post(path, params = {})
      return false if TOKEN.to_s.empty?
      uri = URI("https://api.telegram.org/bot#{TOKEN}/#{path}")
      Rails.logger.debug "[Telegram::Api] POST #{path} params=#{params.inspect}"
      res = Net::HTTP.post_form(uri, params)
      Rails.logger.debug "[Telegram::Api] Response #{path} => #{res.body}"
      JSON.parse(res.body) rescue {}
    end

    # Generic sender used by flows (keeps reply_markup as JSON when needed)
    def self.send_api(path, params = {})
      return false if TOKEN.to_s.empty?
      params = params.transform_keys(&:to_s)
      if params["reply_markup"].is_a?(Hash)
        params["reply_markup"] = params["reply_markup"].to_json
      end
      post(path, params)
    rescue => e
      Rails.logger.error "[Telegram::Api] send_api failed: #{e.class}: #{e.message}"
      nil
    end

    def self.send_with_buttons(chat_id, text, buttons, parse_mode: "Markdown")
      post("sendMessage", { "chat_id" => chat_id.to_s, "text" => text.to_s, "parse_mode" => parse_mode, "reply_markup" => { inline_keyboard: buttons }.to_json })
    end

    def self.send_simple(chat_id, text, parse_mode: "Markdown")
      post("sendMessage", { "chat_id" => chat_id.to_s, "text" => text.to_s, "parse_mode" => parse_mode })
    end

    def self.answer_callback(callback_id, text = nil, show_alert: false)
      post("answerCallbackQuery", { "callback_query_id" => callback_id.to_s, "text" => text.to_s, "show_alert" => show_alert ? "true" : "false" })
    end

    def self.edit_message_with_buttons(chat_id, message_id_or_inline, text, buttons, parse_mode: "Markdown")
      params = { "text" => text.to_s, "parse_mode" => parse_mode, "reply_markup" => { inline_keyboard: buttons }.to_json }
      # numeric message_id (chat + message_id) vs inline_message_id (no chat_id)
      if message_id_or_inline.to_s =~ /\A\d+\z/
        params["chat_id"] = chat_id.to_s
        params["message_id"] = message_id_or_inline.to_i
      else
        params["inline_message_id"] = message_id_or_inline.to_s
      end
      post("editMessageText", params)
    end

    # Send a ForceReply message (helper used by flows)
    def self.send_force_reply(chat_id, text)
      params = {
        chat_id: chat_id,
        text: text,
        reply_markup: { force_reply: true, selective: true }
      }
      send_api("sendMessage", params)
    rescue => e
      Rails.logger.error "[Telegram::Api] send_force_reply failed: #{e.class}: #{e.message}"
      nil
    end

    # Fallback edit without buttons
    def self.edit_message_text(chat_id, message_id, text, parse_mode: "Markdown")
      post("editMessageText", { "chat_id" => chat_id.to_s, "message_id" => message_id.to_i, "text" => text.to_s, "parse_mode" => parse_mode })
    end

    def self.delete_message(chat_id, message_id)
      post("deleteMessage", { "chat_id" => chat_id.to_s, "message_id" => message_id.to_i })
    end
  end
end
