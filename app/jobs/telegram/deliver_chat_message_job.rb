module Telegram
  # Доставка одного сообщения чата одному человеку. Отдельная джоба на
  # получателя: Telegram ограничивает примерно одним сообщением в секунду на
  # чат, и упершаяся в лимит доставка не должна задерживать остальных.
  class DeliverChatMessageJob < ApplicationJob
    class TransientDeliveryError < StandardError; end

    queue_as :default
    retry_on TransientDeliveryError, wait: :polynomially_longer, attempts: 5

    MAX_RETRY_WAIT = 5.minutes
    # Лимит подписи у Telegram вчетверо меньше лимита текста.
    CAPTION_LIMIT = 1024
    # Метка ушедшей шапки переживает и ретраи с растущей паузой, и перенос по
    # retry_after: и то и другое укладывается в считаные минуты.
    HEADER_TTL = 1.hour

    def perform(game_id, recipient_id, text, media = nil, origin = nil)
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
      arming = Telegram::Chat::Session.automatic_start_needed?(
        recipient.telegram_chat_id, recipient, game
      )

      # Кому чат включает сама доставка, карточки не видит: срок жизни чата для
      # него дописываем к первому сообщению, рядом с теми же кнопками.
      text = [ text, Telegram::I18n.t(:chat_lifetime, locale: Telegram::I18n.locale_for(recipient)) ].join("\n\n") if arming

      header, attachment = requests_for(recipient.telegram_chat_id.to_s, text, media)
      # Кнопки вешаем на вложение — то сообщение, ради которого всё и слалось.
      attachment.last["reply_markup"] = { inline_keyboard: Telegram::Chat::Flow.controls(recipient) }.to_json if arming

      delivered = deliver_header(header, game_id, recipient_id, text, media, origin) &&
                  deliver(*attachment, game_id, recipient_id, text, media, origin)
      # Ретрай и постоянная ошибка не должны оставлять человека в чате, о котором
      # он не узнал: сообщение с кнопками до него не дошло. Следующая попытка
      # увидит, что указателя нет, и пришлёт кнопки снова. Запись — только если
      # выбора всё ещё нет: пока шла отправка, человек мог открыть другую игру.
      if arming && delivered
        Telegram::Chat::Session.start_automatically(recipient.telegram_chat_id, recipient, game)
      end
      delivered
    end

    private

    # Что уходит получателю: одно сообщение с текстом либо вложение с шапкой в
    # подписи. Стикер и видеокружок подписи не принимают — им шапка идёт
    # отдельным сообщением перед вложением, иначе не видно, кто и в какую игру
    # прислал.
    def requests_for(chat_id, text, media)
      spec = media && Telegram::Chat::Media.spec(media["kind"])
      return [ nil, text_request(chat_id, text) ] unless spec

      params = { "chat_id" => chat_id, spec[:field] => media["file_id"] }
      return [ nil, [ spec[:method], params.merge("caption" => caption(text)) ] ] if spec[:caption]

      [ text_request(chat_id, text), [ spec[:method], params ] ]
    end

    # Ретрай приходит с теми же аргументами, а упереться в лимит вложение может
    # уже после того, как шапка ушла: без отметки человек получал бы шапку
    # заново на каждой попытке. Отметка привязана к исходному сообщению и
    # получателю — на следующий стикер шапка придёт как обычно. Пропажа отметки
    # безопасна: в худшем случае вернётся сегодняшнее поведение, дубль шапки.
    def deliver_header(header, game_id, recipient_id, text, media, origin)
      return true if header.nil? || header_delivered?(origin, recipient_id)
      return false unless deliver(*header, game_id, recipient_id, text, media, origin)

      Rails.cache.write(header_key(origin, recipient_id), true, expires_in: HEADER_TTL) if origin.present?
      true
    end

    def header_delivered?(origin, recipient_id)
      origin.present? && Rails.cache.exist?(header_key(origin, recipient_id))
    end

    def header_key(origin, recipient_id)
      "tg:chat:header:#{origin}:#{recipient_id}"
    end

    def text_request(chat_id, text)
      # Без parse_mode: это чужой текст, а не наш шаблон. С Markdown одиночный
      # `_` или `[` либо исказит сообщение, либо уронит отправку четырёхсоткой.
      [ "sendMessage", {
        "chat_id" => chat_id,
        "link_preview_options" => Telegram::Api::LINK_PREVIEW_DISABLED,
        "text" => text.to_s
      } ]
    end

    def caption(text)
      text = text.to_s
      text.length > CAPTION_LIMIT ? "#{text[0, CAPTION_LIMIT - 1]}…" : text
    end

    def deliver(path, params, game_id, recipient_id, text, media, origin)
      response = begin
        Telegram::Api.post(path, params)
      rescue StandardError => error
        raise TransientDeliveryError, error.message
      end

      handle_response(response, game_id, recipient_id, text, media, origin)
    end

    def handle_response(response, game_id, recipient_id, text, media, origin)
      return true if response.is_a?(Hash) && response["ok"]

      error_code = response["error_code"].to_i if response.is_a?(Hash)
      raise TransientDeliveryError, "Telegram API did not respond" unless error_code&.positive?
      raise TransientDeliveryError, "Telegram API returned #{error_code}" if error_code >= 500
      return log_failure(error_code, response) unless error_code == 429

      wait = response.dig("parameters", "retry_after").to_i
      wait = 1 if wait <= 0
      return log_failure(error_code, response) if wait > MAX_RETRY_WAIT.to_i

      self.class.set(wait: wait.seconds).perform_later(game_id, recipient_id, text, media, origin)
      false
    end

    def log_failure(error_code, response)
      Rails.logger.warn("[Telegram] chat delivery failed: #{error_code} #{response["description"]}")
      false
    end
  end
end
