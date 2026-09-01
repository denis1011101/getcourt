module Telegram
  # Доставка одного сообщения чата одному человеку. Отдельная джоба на
  # получателя: Telegram ограничивает примерно одним сообщением в секунду на
  # чат, и упершаяся в лимит доставка не должна задерживать остальных.
  class DeliverChatMessageJob < ApplicationJob
    class TransientDeliveryError < StandardError; end

    queue_as :default
    retry_on TransientDeliveryError, wait: :polynomially_longer, attempts: 5

    MAX_RETRY_WAIT = 5.minutes

    def perform(game_id, recipient_id, text)
      game = Game.find_by(id: game_id)
      recipient = User.find_by(id: recipient_id)
      return unless game && recipient && recipient.telegram_chat_id.present?

      # Проверяем участие именно перед отправкой: между постановкой в очередь и
      # доставкой человека могли вывести из состава.
      return unless game.chat_open? && game.team_member_ids.include?(recipient.id)

      # Без parse_mode: это чужой текст, а не наш шаблон. С Markdown одиночный
      # `_` или `[` либо исказит сообщение, либо уронит отправку четырёхсоткой.
      response = begin
        Telegram::Api.post("sendMessage", {
          "chat_id" => recipient.telegram_chat_id.to_s,
          "link_preview_options" => Telegram::Api::LINK_PREVIEW_DISABLED,
          "text" => text.to_s
        })
      rescue StandardError => error
        raise TransientDeliveryError, error.message
      end

      handle_response(response, game_id, recipient_id, text)
    end

    private

    def handle_response(response, game_id, recipient_id, text)
      return true if response.is_a?(Hash) && response["ok"]

      error_code = response["error_code"].to_i if response.is_a?(Hash)
      raise TransientDeliveryError, "Telegram API did not respond" unless error_code&.positive?
      raise TransientDeliveryError, "Telegram API returned #{error_code}" if error_code >= 500
      return log_failure(error_code, response) unless error_code == 429

      wait = response.dig("parameters", "retry_after").to_i
      wait = 1 if wait <= 0
      return log_failure(error_code, response) if wait > MAX_RETRY_WAIT.to_i

      self.class.set(wait: wait.seconds).perform_later(game_id, recipient_id, text)
      false
    end

    def log_failure(error_code, response)
      Rails.logger.warn("[Telegram] chat delivery failed: #{error_code} #{response["description"]}")
      false
    end
  end
end
