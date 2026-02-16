module Geocoding
  class Quota
    DAILY_LIMIT = (ENV["GOOGLE_GEOCODING_DAILY_LIMIT"] || 500).to_i
    CACHE_KEY_PREFIX = "geocoding:google:count".freeze
    EXPIRY = 2.days

    def self.cache_key(date = Date.today)
      "#{CACHE_KEY_PREFIX}:#{date}"
    end

    def self.increment!(by = 1)
      key = cache_key
      Rails.cache.fetch(key, expires_in: EXPIRY) { 0 }
      if Rails.cache.respond_to?(:increment)
        begin
          Rails.cache.increment(key, by)
        rescue => _
          val = (Rails.cache.read(key) || 0) + by
          Rails.cache.write(key, val, expires_in: EXPIRY)
          val
        end
      else
        val = (Rails.cache.read(key) || 0) + by
        Rails.cache.write(key, val, expires_in: EXPIRY)
        val
      end

      if Rails.env.development?
        Rails.logger.debug("[Geocoding::Quota] pid=#{Process.pid} cache=#{Rails.cache.class} key=#{key} +#{by} => #{val.inspect}")
      end
      val
    end

    def self.current
      Rails.cache.read(cache_key).to_i
      val = Rails.cache.read(cache_key).to_i
      Rails.logger.debug("[Geocoding::Quota] pid=#{Process.pid} cache=#{Rails.cache.class} key=#{cache_key} current=#{val}") if Rails.env.development?
      val
    end

    def self.remaining
      [ DAILY_LIMIT - current, 0 ].max
    end

    def self.exceeded?
      current >= DAILY_LIMIT
    end
  end
end
