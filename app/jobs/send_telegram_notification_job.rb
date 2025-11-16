class SendTelegramNotificationJob < ApplicationJob
  queue_as :default

  def perform(chat_id, text)
    TelegramNotifier.send_message(chat_id, text)
  rescue => e
    Rails.logger.warn "SendTelegramNotificationJob failed: #{e.message}"
  end
end
