require "json"
require "net/http"
require "time"
require "uri"

module Weather
  class GoogleForecast
    MAX_HORIZON = 10.days
    CACHE_EXPIRY = 3.hours
    MAX_HOURS = 240
    PAGE_SIZE = 24

    Reading = Data.define(:temperature_c, :condition_type, :description, :precipitation_percent)

    class << self
      def for_game(game)
        return nil if game.environment.to_s == "indoor"

        coordinates = game.court&.coordinates_pair
        return nil unless coordinates

        target_time = game.start_at_for_ui
        return nil unless target_time && target_time >= Time.current && target_time <= Time.current + MAX_HORIZON

        lat, lng = coordinates
        cache_key = "weather:google:#{lat.round(2)}:#{lng.round(2)}:#{target_time.utc.strftime('%Y%m%d%H')}"
        cached = Rails.cache.fetch(cache_key, expires_in: CACHE_EXPIRY) do
          fetch_reading(lat, lng, target_time) || :none
        end

        cached == :none ? nil : cached
      rescue => e
        Rails.logger.warn("Google weather error: #{e.class} #{e.message}")
        nil
      end

      private
        def fetch_reading(lat, lng, target_time)
          key = ENV["GOOGLE_WEATHER_API_KEY"].presence || ENV["GOOGLE_MAPS_API_KEY"].presence
          return nil unless key

          if target_time <= Time.current.end_of_hour
            fetch_current(lat, lng, key)
          else
            fetch_hourly(lat, lng, target_time, key)
          end
        end

        def fetch_current(lat, lng, key)
          data = fetch_page("currentConditions:lookup", lat, lng, key)
          build_reading(data) if data
        end

        def fetch_hourly(lat, lng, target_time, key)
          hours = [ ((target_time - Time.current) / 1.hour).ceil + 1, MAX_HOURS ].min
          query = { hours: hours, pageSize: [ hours, PAGE_SIZE ].min }

          loop do
            data = fetch_page("forecast/hours:lookup", lat, lng, key, query)
            return nil unless data

            forecast = Array(data["forecastHours"]).find { |hour| covers?(hour, target_time) }
            return build_reading(forecast) if forecast

            page_token = data["nextPageToken"].presence
            return nil unless page_token

            query[:pageToken] = page_token
          end
        end

        def fetch_page(endpoint, lat, lng, key, query = {})
          return nil if Weather::Quota.exceeded?

          uri = URI("https://weather.googleapis.com/v1/#{endpoint}")
          uri.query = URI.encode_www_form({
            key: key,
            "location.latitude": lat,
            "location.longitude": lng
          }.merge(query))
          data = fetch_json(uri)
          Weather::Quota.increment! if data
          data
        end

        def covers?(forecast, target_time)
          starts_at = Time.iso8601(forecast.dig("interval", "startTime"))
          ends_at = Time.iso8601(forecast.dig("interval", "endTime"))
          target_time >= starts_at && target_time < ends_at
        rescue ArgumentError, TypeError
          false
        end

        def build_reading(data)
          temperature = data&.dig("temperature", "degrees")
          return nil if temperature.nil?

          Reading.new(
            temperature_c: temperature.to_f,
            condition_type: data.dig("weatherCondition", "type"),
            description: data.dig("weatherCondition", "description", "text"),
            precipitation_percent: data.dig("precipitation", "probability", "percent")
          )
        end

        def fetch_json(uri)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = 5
          http.read_timeout = 10
          response = http.request(Net::HTTP::Get.new(uri))
          JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)
        rescue Net::ReadTimeout, Net::OpenTimeout => e
          Rails.logger.warn("Google weather timeout: #{e.class}")
          nil
        rescue => e
          Rails.logger.warn("Google weather HTTP error: #{e.class} #{e.message}")
          nil
        end
    end
  end
end
