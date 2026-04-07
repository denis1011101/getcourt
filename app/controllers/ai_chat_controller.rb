class AiChatController < ApplicationController
  skip_before_action :authenticate_user!

  def chat
    message = params[:message].to_s.strip
    return render json: { error: "Message is required" }, status: :unprocessable_entity if message.blank?

    locale = I18n.locale.to_s
    service = Ai::AssistantService.new(current_user)
    history = Ai::ChatContextStore.fetch(channel: :web, key: request.session.id)

    begin
      reply = service.chat(message, locale: locale, history: history)
      Ai::ChatContextStore.append(channel: :web, key: request.session.id, user_message: message, assistant_message: reply)
      render json: {
        reply: reply,
        reply_html: helpers.link_telegram_usernames(reply, link_class: "text-indigo-600 dark:text-indigo-300 hover:underline")
      }
    rescue => e
      Rails.logger.error("[AiChatController] #{e.class}: #{e.message}")
      render json: { error: "Sorry, something went wrong. Try again." }, status: :unprocessable_entity
    end
  end
end
