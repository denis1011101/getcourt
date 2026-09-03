module Telegram
  module Chat
    # Вложения, которые чат пересылает как есть. Файл не качаем и не храним:
    # Telegram отдаёт на входящем сообщении file_id и принимает его же обратно
    # на отправку — тот же файл уходит другому человеку одним запросом.
    module Media
      # Тип => метод API, поле с файлом и умеет ли Telegram подпись. Стикер и
      # видеокружок подписи не принимают — шапку им шлём отдельным сообщением.
      SPECS = {
        "animation" => { method: "sendAnimation", field: "animation", caption: true },
        "photo" => { method: "sendPhoto", field: "photo", caption: true },
        "video" => { method: "sendVideo", field: "video", caption: true },
        "audio" => { method: "sendAudio", field: "audio", caption: true },
        "voice" => { method: "sendVoice", field: "voice", caption: true },
        "document" => { method: "sendDocument", field: "document", caption: true },
        "video_note" => { method: "sendVideoNote", field: "video_note", caption: false },
        "sticker" => { method: "sendSticker", field: "sticker", caption: false }
      }.freeze

      class << self
        # Порядок перебора — порядок ключей SPECS, и он значим: гифка приходит
        # сразу двумя полями, animation и document, и переслать её нужно
        # анимацией, иначе у получателя вместо гифки будет файл.
        def from(message)
          kind = SPECS.keys.find { |key| message[key].present? }
          return nil unless kind

          file_id = file_id_for(message[kind])
          return nil if file_id.blank?

          { "kind" => kind, "file_id" => file_id }
        end

        def spec(kind)
          SPECS[kind.to_s]
        end

        private

        # Фото приходит списком размеров, от миниатюры к оригиналу: берём
        # последний, остальные Telegram нарежет получателю сам.
        def file_id_for(value)
          value = value.last if value.is_a?(Array)
          value["file_id"] if value.is_a?(Hash)
        end
      end
    end
  end
end
