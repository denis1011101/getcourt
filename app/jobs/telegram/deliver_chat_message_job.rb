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

      # Отвечать в том же окне, где пришло сообщение, — первое, что делает
      # человек. Без указателя ответ пропадал: Relay не знает, в какую игру его
      # отдать. Поэтому доставка сама включает получателю чат этой игры — но
      # только после того, как сообщение действительно ушло.
      arming = chat_mode_missing?(recipient)

      # Без parse_mode: это чужой текст, а не наш шаблон. С Markdown одиночный
      # `_` или `[` либо исказит сообщение, либо уронит отправку четырёхсоткой.
      params = {
        "chat_id" => recipient.telegram_chat_id.to_s,
        "link_preview_options" => Telegram::Api::LINK_PREVIEW_DISABLED,
        "text" => text.to_s
      }
      params["reply_markup"] = { inline_keyboard: Telegram::Chat::Flow.controls(recipient) }.to_json if arming

      response = begin
        Telegram::Api.post("sendMessage", params)
      rescue StandardError => error
        raise TransientDeliveryError, error.message
      end

      delivered = handle_response(response, game_id, recipient_id, text)
      # Ретрай и постоянная ошибка не должны оставлять человека в чате, о котором
      # он не узнал: сообщение с кнопками до него не дошло. Следующая попытка
      # увидит, что указателя нет, и пришлёт кнопки снова.
      Telegram::Chat::Session.start(recipient.telegram_chat_id, game) if arming && delivered
      delivered
    end

    private

    # Только когда человек не пишет прямо сейчас в другую игру: перебивать чужой
    # выбор молча нельзя, там он сам решил, куда пишет. Спрашиваем active_game, а
    # не сырой указатель: протухший — на удалённую игру или на ту, из состава
    # которой человека вывели, — иначе навсегда заблокировал бы включение.
    def chat_mode_missing?(recipient)
      Telegram::Chat::Session.active_game(recipient.telegram_chat_id, recipient).nil?
    end

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
