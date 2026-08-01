module Weather
  class Quota
    DAILY_LIMIT = (ENV["GOOGLE_WEATHER_DAILY_LIMIT"] || 500).to_i
    CACHE_KEY_PREFIX = "weather:google:count".freeze
    EXPIRY = 2.days

    def self.cache_key(date = Date.current)
      "#{CACHE_KEY_PREFIX}:#{date}"
    end

    def self.increment!(by = 1)
      key = cache_key
      Rails.cache.fetch(key, expires_in: EXPIRY) { 0 }
      value = if Rails.cache.respond_to?(:increment)
        begin
          Rails.cache.increment(key, by)
        rescue
          nil
        end
      end

      if value.nil?
        value = (Rails.cache.read(key) || 0) + by
        Rails.cache.write(key, value, expires_in: EXPIRY)
      end

      value
    end

    def self.current
      Rails.cache.read(cache_key).to_i
    end

    def self.remaining
      [ DAILY_LIMIT - current, 0 ].max
    end

    def self.exceeded?
      current >= DAILY_LIMIT
    end
  end
end
