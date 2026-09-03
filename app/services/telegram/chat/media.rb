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

          value = message[kind]
          value = value.last if value.is_a?(Array)
          return nil unless value.is_a?(Hash) && value["file_id"].present?

          # Тип и размер Telegram сообщает заранее: по ним видно, стоит ли
          # вообще качать файл на страницу игры.
          {
            "kind" => kind,
            "file_id" => value["file_id"],
            "mime_type" => value["mime_type"],
            "file_size" => value["file_size"]
          }.compact
        end

        # В галерею игры идут только те вложения, которые она вообще умеет
        # хранить: фото, видео и гифки. Файлом («документом») отправляют и то и
        # другое, поэтому его пускаем по заявленному типу. Стикеры, голосовые и
        # аудио остаются пересылкой — в галерее игры им делать нечего.
        def attachable?(media)
          return false unless media.is_a?(Hash)
          return false unless %w[photo video animation document].include?(media["kind"])
          return true unless media["kind"] == "document"

          GameMedium::CONTENT_TYPES.include?(media["mime_type"])
        end

        def spec(kind)
          SPECS[kind.to_s]
        end
      end
    end
  end
end
