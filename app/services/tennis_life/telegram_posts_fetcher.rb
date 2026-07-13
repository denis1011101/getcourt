module TennisLife
  class TelegramPostsFetcher
    GIST_API = "https://api.github.com"
    FILENAME = "telegram_posts.json"

    class << self
      def random_post
        posts = fetch_posts
        return nil if posts.empty?

        posts.sample
      end

      def featured_post
        posts = fetch_posts
        return nil if posts.empty?

        Rails.cache.fetch("tennis_life/featured_post", expires_in: 15.minutes) do
          posts.sample
        end
      end

      private

      def fetch_posts
        gist_id = ENV["TELEGRAM_POSTS_GIST_ID"].to_s.strip
        return [] if gist_id.blank?

        Rails.cache.fetch("tennis_life/telegram_posts", expires_in: 30.minutes) do
          raw = fetch_from_api(gist_id)
          next [] if raw.nil?

          parsed = JSON.parse(raw)
          Array(parsed["posts"])
        end
      rescue StandardError => e
        Rails.logger.warn("TennisLife::TelegramPostsFetcher fetch failed: #{e.class}: #{e.message}")
        []
      end

      def fetch_from_api(gist_id)
        uri = URI.parse("#{GIST_API}/gists/#{gist_id}")
        req = Net::HTTP::Get.new(uri)
        req["Accept"] = "application/vnd.github+json"
        req["X-GitHub-Api-Version"] = "2022-11-28"
        token = ENV["TELEGRAM_POSTS_GIST_TOKEN"].to_s.strip
        req["Authorization"] = "Bearer #{token}" if token.present?

        Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 10, open_timeout: 5) do |http|
          res = http.request(req)
          raise "HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)

          extract_file_content(JSON.parse(res.body))
        end
      rescue StandardError => e
        Rails.logger.warn("TennisLife::TelegramPostsFetcher API error: #{e.class}: #{e.message}")
        nil
      end

      def extract_file_content(body)
        entry = body.dig("files", FILENAME)
        raise "#{FILENAME} not found in gist" unless entry

        entry["content"].to_s
      end
    end
  end
end
