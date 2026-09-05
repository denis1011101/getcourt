require "net/http"
require "uri"
require "json"
require "securerandom"
require "tempfile"

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
    def self.send_api(path, params = {}, silent: nil)
      params = params.transform_keys(&:to_s)
      if params["reply_markup"].is_a?(Hash)
        params["reply_markup"] = params["reply_markup"].to_json
      end
      params = QuietHours.apply(params, silent: silent) if path.to_s.start_with?("send")
      post(path, params)
    rescue => e
      Rails.logger.error "[Telegram::Api] send_api failed: #{e.class}: #{e.message}"
      nil
    end

    # Превью ссылки телеграм рисует из своего кэша и обновляет его, когда сам
    # сочтёт нужным: под приглашением висела карточка чужого корта и чужой даты.
    # Всё нужное и так есть в тексте, поэтому по умолчанию превью выключено.
    LINK_PREVIEW_DISABLED = { is_disabled: true }.to_json

    # Ночная тишина живёт в именованных отправителях, а не в post: post — сырой
    # транспорт, и через него же уходит сообщение чата, которому звенеть можно
    # в любой час. Вызывающий может решить и сам — параметром silent.
    def self.send_with_buttons(chat_id, text, buttons, parse_mode: "Markdown", link_preview: false, silent: nil)
      params = { "chat_id" => chat_id.to_s, "text" => text.to_s, "reply_markup" => { inline_keyboard: buttons }.to_json }
      params["parse_mode"] = parse_mode if parse_mode.present?
      params["link_preview_options"] = LINK_PREVIEW_DISABLED unless link_preview
      post("sendMessage", QuietHours.apply(params, silent: silent))
    end

    def self.send_simple(chat_id, text, parse_mode: "Markdown", link_preview: false, silent: nil)
      params = { "chat_id" => chat_id.to_s, "text" => text.to_s }
      params["parse_mode"] = parse_mode if parse_mode.present?
      params["link_preview_options"] = LINK_PREVIEW_DISABLED unless link_preview
      post("sendMessage", QuietHours.apply(params, silent: silent))
    end

    def self.send_photo(chat_id, photo_path, caption: nil, parse_mode: nil, silent: nil)
      return false if TOKEN.to_s.empty?

      silent = QuietHours.silent?(chat_id) if silent.nil?
      uri = URI("https://api.telegram.org/bot#{TOKEN}/sendPhoto")
      boundary = "----GetCourtTelegram#{SecureRandom.hex(12)}"
      body = String.new.b

      add_multipart_field(body, boundary, "chat_id", chat_id.to_s)
      add_multipart_field(body, boundary, "caption", caption.to_s) if caption.present?
      add_multipart_field(body, boundary, "parse_mode", parse_mode.to_s) if parse_mode.present?
      # Тишину сюда приходится вписывать руками: картинка уходит своим
      # multipart-запросом, мимо post и мимо QuietHours.apply.
      add_multipart_field(body, boundary, "disable_notification", "true") if silent
      add_multipart_file(body, boundary, "photo", photo_path, "image/png")
      body << "--#{boundary}--\r\n".b

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      request.body = body

      Rails.logger.debug "[Telegram::Api] POST sendPhoto chat_id=#{chat_id.inspect} photo=#{photo_path.inspect}"
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
      Rails.logger.debug "[Telegram::Api] Response sendPhoto => #{response.body}"
      JSON.parse(response.body) rescue {}
    end

    # Bot API отдаёт файл в два шага: getFile возвращает путь, живущий около
    # часа, и уже по нему файл качается. Пишем в Tempfile потоком, а не в
    # строку: у прода гигабайт памяти, а вложение бывает и двадцатимегабайтным.
    # Больше 20 МБ бот забрать не может — это ограничение самого API.
    def self.download_file(file_id)
      result = post("getFile", { "file_id" => file_id.to_s })
      path = result.dig("result", "file_path") if result.is_a?(Hash)
      return nil if path.blank?

      file = Tempfile.new("telegram-file", binmode: true)
      begin
        fetch_file(URI("https://api.telegram.org/file/bot#{TOKEN}/#{path}"), file) ? [ file, File.basename(path) ] : discard_file(file)
      rescue StandardError => e
        Rails.logger.warn("[Telegram::Api] download_file failed: #{e.class}: #{e.message}")
        discard_file(file)
      end
    end

    def self.fetch_file(uri, file)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        http.request(Net::HTTP::Get.new(uri)) do |response|
          return false unless response.is_a?(Net::HTTPSuccess)

          response.read_body { |chunk| file.write(chunk) }
        end
      end
      file.rewind
      true
    end

    # Неудача на любом шаге — и временный файл надо убрать здесь: наружу он не
    # уходит, а значит, закрыть его вызывающему коду уже не за что.
    def self.discard_file(file)
      file.close
      file.unlink
      nil
    end

    def self.answer_callback(callback_id, text = nil, show_alert: false)
      post("answerCallbackQuery", { "callback_query_id" => callback_id.to_s, "text" => text.to_s, "show_alert" => show_alert ? "true" : "false" })
    end

    def self.edit_message_with_buttons(chat_id, message_id_or_inline, text, buttons, parse_mode: "Markdown")
      params = { "text" => text.to_s, "reply_markup" => { inline_keyboard: buttons }.to_json }
      params["parse_mode"] = parse_mode if parse_mode.present?
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
      params = { "chat_id" => chat_id.to_s, "message_id" => message_id.to_i, "text" => text.to_s }
      params["parse_mode"] = parse_mode if parse_mode.present?
      post("editMessageText", params)
    end

    def self.delete_message(chat_id, message_id)
      post("deleteMessage", { "chat_id" => chat_id.to_s, "message_id" => message_id.to_i })
    end

    def self.add_multipart_field(body, boundary, name, value)
      body << "--#{boundary}\r\n".b
      body << "Content-Disposition: form-data; name=\"#{name}\"\r\n\r\n".b
      body << value.to_s.b
      body << "\r\n".b
    end
    private_class_method :add_multipart_field

    def self.add_multipart_file(body, boundary, name, path, content_type)
      body << "--#{boundary}\r\n".b
      body << "Content-Disposition: form-data; name=\"#{name}\"; filename=\"#{File.basename(path)}\"\r\n".b
      body << "Content-Type: #{content_type}\r\n\r\n".b
      body << File.binread(path)
      body << "\r\n".b
    end
    private_class_method :add_multipart_file
  end
end
