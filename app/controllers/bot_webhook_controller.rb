class BotWebhookController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!

  # POST /bot_webhook
  def receive
    Rails.logger.info("[BOT] receive raw params: #{params.to_unsafe_h.slice('update_id','message').inspect}")
    update = params.to_unsafe_h
    Telegram::UpdateService.process(update)
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
