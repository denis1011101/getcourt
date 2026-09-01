module Telegram
  module Chat
    # Как выглядит сообщение чата у получателя. Подпись отделена от текста
    # намеренно: имя своё, а тело — чужое, и склеивать их в один шаблон с
    # разметкой нельзя.
    module Message
      def self.render(game:, sender:, body:)
        [ header(game, sender), body.to_s ].join("\n")
      end

      def self.header(game, sender)
        name = Telegram::Helpers::UserLookup.display_name(sender, fallback: "?")
        "💬 #{game_label(game)} · #{name}"
      end

      def self.game_label(game)
        city = game.court&.city_name.presence
        date = game.date&.strftime("%d.%m")
        [ "##{game.id}", city, date ].compact.join(" ")
      end
    end
  end
end
