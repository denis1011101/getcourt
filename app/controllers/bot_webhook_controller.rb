class BotWebhookController < ActionController::API
  skip_before_action :verify_authenticity_token

  # POST /bot_webhook
  def receive
    update = params.to_unsafe_h

    message = update['message'] || update['edited_message'] || update['channel_post'] || {}
    chat = message['chat'] || {}
    from = message['from'] || {}
    text = message['text'].to_s.strip

    # handle registration: "/register TOKEN"
    if text =~ %r{\A/register\s+([0-9a-fA-F]+)\z}i
      token = $1
      user = User.find_by(telegram_registration_token: token)
      if user
        chat_id = chat['id']
        user.update(telegram_chat_id: chat_id)
        user.clear_telegram_registration_token! rescue nil
        # optional: reply via API (not required) — use TelegramNotifier
        TelegramNotifier.send_message(chat_id, "Registration complete. You will receive notifications here.")
      end
    end

    head :ok
  rescue => e
    Rails.logger.error "Bot webhook error: #{e.class} #{e.message}\n#{e.backtrace.first(10).join("\n")}"
    head :internal_server_error
  end
end
