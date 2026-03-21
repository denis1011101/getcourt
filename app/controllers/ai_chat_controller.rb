class AiChatController < ApplicationController
  skip_before_action :authenticate_user!

  def chat
    message = params[:message].to_s.strip
    return render json: { error: "Message is required" }, status: :unprocessable_entity if message.blank?

    locale = I18n.locale.to_s
    service = Ai::AssistantService.new(current_user)

    begin
      reply = service.chat(message, locale: locale)
      render json: { reply: reply }
    rescue => e
      Rails.logger.error("[AiChatController] #{e.class}: #{e.message}")
      render json: { error: "Sorry, something went wrong. Try again." }, status: :unprocessable_entity
    end
  end
end
