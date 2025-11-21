class BotWebhookController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!

  # POST /bot_webhook
  def receive
    update = params.to_unsafe_h
    message = update['message'] || {}
    chat = message['chat'] || {}
    text = message['text'].to_s.strip

    if text =~ %r{\A/register\s+([0-9a-fA-F]+)\z}i
      token = $1
      user = User.find_by(telegram_registration_token: token)
      if user && chat['id']
        chat_id = chat['id'].to_s

        User.transaction do
          # очистить chat_id у других пользователей
          User.where(telegram_chat_id: chat_id).where.not(id: user.id).update_all(telegram_chat_id: nil)
          # присвоить текущему пользователю
          user.update!(telegram_chat_id: chat_id)
          user.clear_telegram_registration_token! rescue nil
        end

        TelegramNotifier.send_message(chat_id, "Registration complete. You will receive notifications here.")
      else
        TelegramNotifier.send_message(chat['id'], "Invalid or expired token.") if chat['id']
      end
    end

    head :ok
  rescue ActiveRecord::RecordNotUnique => e
    Rails.logger.warn "Telegram registration race condition: #{e.message}"
    # можно пробовать повторить: найти предыдущего владельца и очистить, затем retry один раз
    head :conflict
  rescue => e
    Rails.logger.error "Bot webhook error: #{e.class} #{e.message}"
    head :internal_server_error
  end
end
