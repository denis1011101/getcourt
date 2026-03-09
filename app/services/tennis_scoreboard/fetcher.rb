module TennisScoreboard
  class Fetcher
    GIST_API = "https://api.github.com"
    FILENAME = "sport_events.txt"

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

        gist_id = extract_gist_id(gist_url)
        unless gist_id
          Rails.logger.warn("TennisScoreboard::Fetcher invalid gist URL: #{gist_url}")
          return nil
        end

        Rails.cache.fetch("tennis_life/tennis_score_raw", expires_in: 30.minutes) do
          fetch_from_api(gist_id)
        end
      rescue StandardError => e
        Rails.logger.warn("TennisScoreboard::Fetcher fetch failed: #{e.class}: #{e.message}")
        nil
      end

      def fetch_from_api(gist_id)
        uri = URI.parse("#{GIST_API}/gists/#{gist_id}")
        req = Net::HTTP::Get.new(uri)
        req["Accept"] = "application/vnd.github+json"
        req["X-GitHub-Api-Version"] = "2022-11-28"
        token = ENV["TENNIS_SCORE_GIST_TOKEN"].to_s.strip
        req["Authorization"] = "Bearer #{token}" if token.present?

        Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 10, open_timeout: 5) do |http|
          res = http.request(req)
          raise "HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)

          extract_file_content(JSON.parse(res.body))
        end
      rescue StandardError => e
        Rails.logger.warn("TennisScoreboard::Fetcher API error: #{e.class}: #{e.message}")
        nil
      end

      def extract_file_content(body)
        entry = body.dig("files", FILENAME)
        raise "#{FILENAME} not found in gist" unless entry

        entry["content"].to_s
      end

      def extract_gist_id(url)
        url.match(%r{\Ahttps?://gist\.github(?:usercontent)?\.com/[^/]+/([a-f0-9]+)})&.captures&.first
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
    end
  end
end
