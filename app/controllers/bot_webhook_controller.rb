class BotWebhookController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!

  # POST /bot_webhook
  def create
    # optional: validate secret token if you set one via setWebhook(secret_token: ...)
    secret = ENV["TELEGRAM_WEBHOOK_SECRET"].to_s
    incoming = request.headers["X-Telegram-Bot-Api-Secret-Token"].to_s
    if secret.present? && !ActiveSupport::SecurityUtils.secure_compare(incoming, secret)
      Rails.logger.warn "[BOT] webhook secret mismatch"
      head :forbidden and return
    end

    if request.raw_post.present?
      begin
        update = JSON.parse(request.raw_post)
      rescue JSON::ParserError => e
        Rails.logger.warn "[BotWebhook] JSON parse error: #{e.message}"
        update = params.to_unsafe_h
      end
    else
      update = params.to_unsafe_h
    end

    if update["callback_query"]
      Telegram::CallbackHandler.handle(update["callback_query"])
    elsif update["message"]
      Telegram::MessageHandler.handle(update["message"])
    elsif update["edited_message"]
      Telegram::MessageHandler.handle(update["edited_message"])
    end

    head :ok
  rescue => e
    Rails.logger.error "[BotWebhook] #{e.class} #{e.message}"
    head :ok
  end
end
