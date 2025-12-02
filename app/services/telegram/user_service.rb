module Telegram
  class UserService
    # Найти или создать пользователя по данным чата Telegram.
    # Возвращает [user, created_bool]
    def self.find_or_create_for_chat(chat_hash)
      Rails.logger.info("[BOT] UserService.find_or_create_for_chat chat=#{chat_hash.inspect}")
      chat_id  = chat_hash['id'].to_s
      username = chat_hash['username'].to_s.presence
      first_name = (chat_hash['first_name'] || chat_hash.dig('from','first_name')).to_s.presence || "Telegram user"

      # 1) уже привязан по chat_id
      if (u = User.find_by(telegram_chat_id: chat_id))
        return [u, false]
      end

      # 2) попытка найти по username и привязать chat_id
      if username && (u = User.find_by(telegram_username: username))
        u.update_column(:telegram_chat_id, chat_id) unless u.telegram_chat_id == chat_id
        return [u, false]
      end

      # 3) создать минимальный аккаунт, пометить источник и сгенерировать сложный email
      random_email = "tg-#{SecureRandom.hex(18)}@telegram.getcourt"
      u = nil

      User.transaction do
        u = User.create!(
          email: random_email,
          name: first_name,
          telegram_username: username,
          telegram_chat_id: chat_id,
          registration_source: "telegram",
          telegram_generated_email: true
        )
        Rails.logger.info("[BOT] created user id=#{u.id} email=#{u.email}")
      end

      [u, true]
    rescue ActiveRecord::RecordNotUnique => e
      Rails.logger.warn "Telegram UserService race condition: #{e.message}"
      # попробуем вернуть существующего пользователя по chat_id
      [User.find_by(telegram_chat_id: chat_id) || User.find_by(telegram_username: username), false]
    end
  end
end
