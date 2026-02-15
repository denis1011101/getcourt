class SendTelegramNotificationJob < ApplicationJob
  queue_as :default

  def perform(chat_id, text, parse_mode: nil)
    TelegramNotifier.send_message(chat_id, text, parse_mode: parse_mode)
  rescue => e
    Rails.logger.warn "SendTelegramNotificationJob failed: #{e.message}"
  end
end
