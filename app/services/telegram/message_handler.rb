module Telegram
  class MessageHandler
    def self.handle(message)
      chat_id = message.dig("chat","id") || message.dig("from","id")
      text = message["text"].to_s.strip
      return unless chat_id && text.present?

      key = "tg:conv:#{chat_id}"
      conv = Rails.cache.read(key)
      return unless conv

      user = User.find_by(telegram_chat_id: chat_id)
      unless user
        Api.send_simple(chat_id, "Cannot find your account. Please link your Telegram in your profile.")
        Rails.cache.delete(key)
        return
      end

      case conv["step"]
      when "ask_singles_hours"
        res = parse_or_skip(text)
        if res == :invalid
          Api.send_force_reply(chat_id, "Couldn't parse number. Reply with singles hours (e.g. 1.5) or type 'skip'.")
          return
        end

        conv["singles_hours"] = (res == :skip ? nil : res)
        conv["step"] = "ask_doubles_hours"
        Rails.cache.write(key, conv, expires_in: 2.hours)
        Api.send_force_reply(chat_id, "Please reply with doubles hours (e.g. 0 or 1.5) or type 'skip'.")

      when "ask_doubles_hours"
        res = parse_or_skip(text)
        if res == :invalid
          Api.send_force_reply(chat_id, "Couldn't parse number. Reply with doubles hours (e.g. 0 or 1.5) or type 'skip'.")
          return
        end

        conv["doubles_hours"] = (res == :skip ? nil : res)
        # persist (allow nil values)
        stats = user.player_statistic || user.build_player_statistic
        stats.singles_hours = conv["singles_hours"]
        stats.doubles_hours = conv["doubles_hours"]
        stats.save!
        Api.send_simple(chat_id, "Thanks — statistics saved.\nSingles hours: #{stats.singles_hours}\nDoubles hours: #{stats.doubles_hours}")
        Rails.cache.delete(key)
      else
        Api.send_simple(chat_id, "No active flow. Use the button again to start.")
        Rails.cache.delete(key)
      end
    rescue => e
      Rails.logger.error "[Telegram::MessageHandler] #{e.class} #{e.message}"
      Api.send_simple(chat_id, "An error occurred while processing your reply.")
      Rails.cache.delete(key)
    end

    def self.parse_or_skip(str)
      return :skip if str =~ /\A\s*(skip|-|none)\s*\z/i
      return :invalid if str.blank?
      Float(str) rescue :invalid
    end

    def self.parse_float(str)
      Float(str) rescue nil
    end
  end
end
