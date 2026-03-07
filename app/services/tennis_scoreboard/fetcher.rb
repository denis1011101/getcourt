# TODO: перевести fetch_raw_text с сырого raw-URL (TENNIS_SCORE_GIST_URL + normalize_gist_url)
#       на GitHub API (GET /gists/:id + dig("files", filename, "content")),
#       по аналогии с TennisLife::TelegramPostsFetcher.
module TennisScoreboard
  class Fetcher
    class << self
      def raw_text
        fetch_raw_text
      end

      def tennis_block(raw_text)
        extract_tennis_block(raw_text)
      end

      def telegram_text
        text = raw_text
        return if text.blank?

        tennis = tennis_block(text)
        return if tennis.blank?

        plain = strip_html(tennis).strip
        return if plain.blank?

        plain.truncate(1800, separator: "\n", omission: "\n...")
      end

      private

      def fetch_raw_text
        gist_url = ENV["TENNIS_SCORE_GIST_URL"].to_s.strip
        return if gist_url.blank?

        Rails.cache.fetch("tennis_life/tennis_score_raw", expires_in: 30.minutes) do
          uri = URI.parse(normalize_gist_url(gist_url))
          allowed_hosts = %w[gist.github.com gist.githubusercontent.com]
          raise ArgumentError, "Unsupported scoreboard host: #{uri.host}" unless allowed_hosts.include?(uri.host)

          req = Net::HTTP::Get.new(uri)
          token = ENV["TENNIS_SCORE_GIST_TOKEN"].to_s.strip
          req["Authorization"] = "Bearer #{token}" if token.present?

          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 10, open_timeout: 5) do |http|
            res = http.request(req)
            raise "HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)

            res.body.to_s
          end
        end
      rescue StandardError => e
        Rails.logger.warn("TennisScoreboard::Fetcher fetch failed: #{e.class}: #{e.message}")
        nil
      end

      def extract_tennis_block(raw_text)
        text = raw_text.to_s
          .dup
          .force_encoding(Encoding::UTF_8)
          .encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "")

        normalized = text.gsub("\r\n", "\n")
        stop_at = normalized.index(/<b>\s*(Футбол|Хоккей|Баскетбол)\b/i)
        stop_at ? normalized[0...stop_at] : normalized
      end

      def strip_html(text)
        text
          .gsub(%r{<\s*br\s*/?\s*>}i, "\n")
          .gsub(%r{</?(b|i)\b[^>]*>}i, "")
          .gsub(%r{<[^>]+>}, "")
          .gsub(/[ \t]+\n/, "\n")
          .gsub(/\n{3,}/, "\n\n")
      end

      def normalize_gist_url(url)
        return url if url.include?("gist.githubusercontent.com")

        match = url.match(%r{\Ahttps?://gist\.github\.com/([^/]+)/([a-f0-9]+)})
        return url unless match

        "https://gist.githubusercontent.com/#{match[1]}/#{match[2]}/raw"
      end
    end
  end
end
