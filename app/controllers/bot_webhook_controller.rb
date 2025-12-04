class BotWebhookController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!

  # POST /bot_webhook
  def receive
    # optional: validate secret token if you set one via setWebhook(secret_token: ...)
    secret = ENV["TELEGRAM_WEBHOOK_SECRET"].to_s
    incoming = request.headers["X-Telegram-Bot-Api-Secret-Token"].to_s
    if secret.present? && !ActiveSupport::SecurityUtils.secure_compare(incoming, secret)
      Rails.logger.warn "[BOT] webhook secret mismatch"
      head :forbidden and return
    end

    update = params.to_unsafe_h
    Telegram::UpdateJob.perform_later(update)
    head :ok
  rescue ActiveRecord::RecordNotUnique => e
    Rails.logger.warn "Telegram registration race condition: #{e.message}"
    head :conflict
  rescue => e
    Rails.logger.error "Bot webhook error: #{e.class} #{e.message}"
    head :internal_server_error
  end
end
