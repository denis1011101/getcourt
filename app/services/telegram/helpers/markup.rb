require "cgi"
require "uri"

module Telegram
  module Helpers
    # Имя корта — ссылка, и в приглашении, и в напоминании. Ради неё сообщение
    # уходит в телеграм с parse_mode: HTML, а значит всё, что ввели люди,
    # придётся экранировать. В письме тот же текст собирается без разметки:
    # @body вставляется и в текстовый шаблон, где теги видно как есть.
    module Markup
      module_function

      def markup?(channel)
        channel.to_s == "telegram"
      end

      # Экранирует, только когда текст пойдёт размеченным.
      def escaper(channel)
        markup = markup?(channel)
        ->(value) { markup ? CGI.escapeHTML(value.to_s) : value.to_s }
      end

      # Готовое имя корта: в телеграме ссылкой, в письме просто именем.
      def court_name(court, base_url:, channel:)
        name = court&.name.to_s.strip
        return nil if name.blank?

        esc = escaper(channel)
        url = markup?(channel) ? court_url(court, base_url) : nil
        return esc.call(name) if url.blank?

        %(<a href="#{esc.call(url)}">#{esc.call(name)}</a>)
      end

      # Хост берём у ссылки на игру: она пришла из запроса и верна и на проде,
      # и локально.
      def court_url(court, base_url)
        return nil if court&.id.blank? || base_url.blank?

        uri = URI.parse(base_url)
        uri.path = "/courts/#{court.id}"
        uri.query = nil
        uri.fragment = nil
        uri.to_s
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
