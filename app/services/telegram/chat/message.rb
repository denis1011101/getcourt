module Telegram
  module Chat
    # Как выглядит сообщение чата у получателя. Подпись отделена от текста
    # намеренно: имя своё, а тело — чужое, и склеивать их в один шаблон с
    # разметкой нельзя.
    module Message
      # Подписи у вложения может не быть — тогда сообщение это одна шапка.
      def self.render(game:, sender:, body:, locale: Telegram::I18n::DEFAULT_LOCALE)
        [ header(game, sender, locale), body.to_s.presence ].compact.join("\n")
      end

      # Дата в шапке — на языке того, кто её читает: «03.09.2026» и «09/03/2026»
      # это один день, и угадывать, какой формат перед ним, человек не должен.
      def self.header(game, sender, locale = Telegram::I18n::DEFAULT_LOCALE)
        name = Telegram::Helpers::UserLookup.display_name(sender, fallback: "?")
        "💬 #{game_label(game, locale: locale)} · #{name}"
      end

      # Дата — ближайшая: у еженедельной игры дата создания давно прошла, а в
      # чат пишут про сегодняшний состав. Формат берём полный, из локали:
      # короткое «14.05» рядом со временем сообщения читается как часы.
      def self.game_label(game, locale: Telegram::I18n::DEFAULT_LOCALE)
        city = game.court&.city_name.presence
        date = game.respond_to?(:next_date) ? (game.next_date || game.date) : game.date
        date_text = date ? ::I18n.l(date, format: :telegram, locale: locale) : nil
        [ "##{game.id}", city, date_text ].compact.join(" ")
      end
    end
  end
end
