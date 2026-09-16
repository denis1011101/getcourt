require "net/http"
require "json"

module Social
  module Content
    # Анонс релиза. Текст — секция «## Highlights» из тела GitHub Release: её
    # пишем руками при запуске release.yml, остальное тело — автосписок PR
    # по-русски, в англоязычную ленту он не идёт. Нет секции — нет поста:
    # релиз из одних обновлений зависимостей анонсировать нечем.
    #
    # Ключ — сам тег: он и так уникален, а дедуп по (network, kind, dedup_key)
    # не даст повторному деплою того же тега запостить дважды.
    class Release < Base
      TAG = /\Av\d+\.\d+\.\d+\z/
      HEADING = /\A##\s+Highlights\s*\z/i
      # Шапка и ссылка съедают ~90 графем из 300 на Bluesky — столько остаётся
      # на текст. release.yml проверяет ту же цифру до создания релиза.
      HIGHLIGHTS_LIMIT = 200

      class FetchError < StandardError; end

      def self.from_key(dedup_key)
        tag = dedup_key.to_s
        tag.match?(TAG) ? new(tag) : nil
      end

      # .env-example держит GITHUB_REPO= пустым — пустая строка тоже дефолт,
      # как и в script/deploy.
      def self.repo
        ENV["GITHUB_REPO"].presence || "denis1011101/getcourt"
      end

      # Репозиторий публичный — токен не нужен, а один запрос на релиз в лимит
      # 60/час не упирается. 404 — релиза нет, всё остальное — ошибка, пусть
      # джоба упадёт и попадёт в failed, а не притворится, что постить нечего.
      def self.fetch(tag)
        uri = URI("https://api.github.com/repos/#{repo}/releases/tags/#{tag}")
        response = Net::HTTP.get_response(uri, { "Accept" => "application/vnd.github+json", "User-Agent" => "getcourt" })

        case response
        when Net::HTTPSuccess then JSON.parse(response.body)
        when Net::HTTPNotFound then nil
        else raise FetchError, "GitHub returned #{response.code} for #{tag}"
        end
      end

      attr_reader :tag

      def initialize(tag, release: :unfetched)
        @tag = tag.to_s
        @release = release
      end

      def kind
        "release"
      end

      def dedup_key
        tag
      end

      def available?
        release.present? && !release["draft"] && highlights.present?
      end

      def image_url
        Social.logo_url
      end

      def url
        release&.dig("html_url") || Social.app_url
      end

      # Что не так с материалом — для rake-задачи и лога деплоя.
      def unavailable_reason
        return nil if available?
        return "no such release on GitHub" if release.nil?
        return "release is still a draft" if release["draft"]

        "no ## Highlights section — nothing to announce"
      end

      # Между «## Highlights» и следующим заголовком любого уровня. Хэштег
      # («#GetCourt») заголовком не считается — после решётки нет пробела.
      def highlights
        lines = release&.dig("body").to_s.lines.map { |line| line.chomp.delete_suffix("\r") }
        start = lines.index { |line| line.match?(HEADING) }
        return nil unless start

        lines[(start + 1)..].take_while { |line| !line.match?(/\A#+\s/) }.join("\n").strip.presence
      end

      private

      def release
        @release = self.class.fetch(tag) if @release == :unfetched
        @release
      end

      # Ссылку даём со схемой — иначе Bluesky не соберёт link-facet.
      def body(locale:)
        "🎾 GetCourt #{tag} is out\n\n#{highlights}\n\n#{url}"
      end
    end
  end
end
