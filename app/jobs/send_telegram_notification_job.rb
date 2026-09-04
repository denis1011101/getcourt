class SendTelegramNotificationJob < ApplicationJob
  queue_as :default

  def perform(chat_id, text, parse_mode: nil, silent: false)
    TelegramNotifier.send_message(chat_id, text, parse_mode: parse_mode, silent: silent)
  rescue => e
    Rails.logger.warn "SendTelegramNotificationJob failed: #{e.message}"
  end
end
