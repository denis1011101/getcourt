class AiChatController < ApplicationController
  HISTORY_TTL = 10.minutes
  HISTORY_LIMIT = 6

  skip_before_action :authenticate_user!

  def chat
    message = params[:message].to_s.strip
    return render json: { error: "Message is required" }, status: :unprocessable_entity if message.blank?

    locale = I18n.locale.to_s
    service = Ai::AssistantService.new(current_user)
    history = Rails.cache.read(history_cache_key) || []

    begin
      reply = service.chat(message, locale: locale, history: history)
      Rails.cache.write(history_cache_key, updated_history(history, message, reply), expires_in: HISTORY_TTL)
      render json: {
        reply: reply,
        reply_html: helpers.link_telegram_usernames(reply, link_class: "text-indigo-600 dark:text-indigo-300 hover:underline")
      }
    rescue => e
      Rails.logger.error("[AiChatController] #{e.class}: #{e.message}")
      render json: { error: "Sorry, something went wrong. Try again." }, status: :unprocessable_entity
    end
  end

  private

  def history_cache_key
    "ai_chat/history/#{request.session.id}"
  end

  def updated_history(history, message, reply)
    Array(history).last(HISTORY_LIMIT - 2) + [
      { role: "user", content: message.to_s },
      { role: "assistant", content: reply.to_s }
    ]
  end
end
