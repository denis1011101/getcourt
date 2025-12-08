class BotWebhookController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!

  # POST /bot_webhook
  def create
    # validate secret token if configured
    expected = ENV["TELEGRAM_WEBHOOK_SECRET"].to_s.presence
    received = request.headers["X-Telegram-Bot-Api-Secret-Token"]
    if expected && expected != received
      Rails.logger.warn "[BotWebhook] webhook secret mismatch from #{request.remote_ip}"
      head :forbidden and return
    end

    raw = request.raw_post.to_s
    update = begin
      JSON.parse(raw)
    rescue JSON::ParserError
      # some reverse proxies / clients may nest payload under "bot_webhook"
      params[:bot_webhook] || params.to_unsafe_h
    end

    # if the payload was wrapped (as seen in logs), unwrap
    update = update["bot_webhook"] if update.is_a?(Hash) && update.key?("bot_webhook")

    # enqueue processing (async) — safe for production
    Telegram::UpdateJob.perform_later(update)

    head :ok
  rescue => e
    Rails.logger.error "[BotWebhook] #{e.class}: #{e.message}\n#{e.backtrace.first(10).join("\n")}"
    head :internal_server_error
  end
end
