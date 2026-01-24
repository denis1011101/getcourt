module Telegram
  class UpdateTelegramUsernamesJob < ApplicationJob
    queue_as :default

    BATCH_SIZE = 200
    SLEEP_BETWEEN_CALLS_SEC = 0.03 # чтобы не упираться в лимиты Telegram

    def perform(limit: nil)
      scope = User.where.not(telegram_chat_id: nil)
      scope = scope.limit(limit) if limit.present?

      poller = Telegram::Poller.new
      updated = 0
      checked = 0

      scope.find_each(batch_size: BATCH_SIZE) do |user|
        checked += 1
        chat_id = user.telegram_chat_id.to_s

        resp = poller.send_api("getChat", { chat_id: chat_id })
        username = resp.dig("result", "username").to_s.strip

        # если username отсутствует (у многих пользователей его нет) — не затираем
        next if username.empty?
        next if username == user.telegram_username.to_s

        user.update_columns(telegram_username: username, updated_at: Time.current)
        updated += 1

        sleep SLEEP_BETWEEN_CALLS_SEC
      rescue => e
        Rails.logger.warn("[UpdateTelegramUsernamesJob] user_id=#{user&.id} chat_id=#{chat_id} #{e.class}: #{e.message}")
      end

      Rails.logger.info("[UpdateTelegramUsernamesJob] checked=#{checked} updated=#{updated}")
    end
  end
end
