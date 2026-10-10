# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Geocoding
  class AddressResolver
    NOMINATIM_MUTEX = Mutex.new

    class << self
      attr_accessor :nominatim_last_request_at
    end
    self.nominatim_last_request_at = -Float::INFINITY

    # Resolves lat/lng to { address: String, city_name: String | nil, street: String | nil,
    # country_code: "RU" | nil, city_component: String | nil } or nil.
    # city_component — тип компонента, из которого взято city_name: у Google
    # locality / postal_town / administrative_area_level_2, у Nominatim ключ
    # address (city / town / village / municipality). По нему Cities::Resolver
    # отличает город от административной единицы.
    # Tries Google first, falls back to Nominatim.
    def resolve(lat, lng)
      geocode_google_full(lat, lng) || geocode_nominatim_structured(lat, lng)
    end

    # Forward geocoding: text string -> [lat, lng] or nil.
    def self.geocode_text(str)
      resolver = new
      resolver.send(:geocode_text_google, str) || resolver.send(:geocode_text_nominatim, str)
    end

    # Pure haversine distance in km.
    def self.haversine_km(lat1, lon1, lat2, lon2)
      rad = Math::PI / 180
      dlat = (lat2 - lat1) * rad
      dlon = (lon2 - lon1) * rad
      a = Math.sin(dlat / 2)**2 +
          Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dlon / 2)**2
      6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    end

    private

    def geocode_google_full(lat, lng)
      key = ENV["GOOGLE_GEOCODING_API_KEY"]
      return nil if key.to_s.strip.empty?

      url = URI("https://maps.googleapis.com/maps/api/geocode/json" \
                "?latlng=#{lat},#{lng}&key=#{key}&language=en")
      data = fetch_json(url)
      return nil unless data && data["status"] == "OK" && data["results"].any?

      components = data["results"].first["address_components"]
      street  = gcomp(components, "route")
      number  = gcomp(components, "street_number")
      city, city_component = gcomp_typed(components, "locality", "postal_town", "administrative_area_level_2")
      country = gcomp(components, "country")
      country_code = normalize_country_code(gcomp(components, "country", name: "short_name"))

      street_line = [ street, number ].compact.join(" ").presence
      address = [ street_line, city, country ].compact.join(", ").presence

      { address: address, city_name: city, street: street_line,
        country_code: country_code, city_component: city_component }
    rescue => e
      Rails.logger.warn("Google geocoding error: #{redact_key(e.message)}")
      nil
    end

    def geocode_text_google(str)
      key = ENV["GOOGLE_GEOCODING_API_KEY"]
      return nil if key.to_s.strip.empty?

      url = URI("https://maps.googleapis.com/maps/api/geocode/json" \
                "?address=#{URI.encode_www_form_component(str)}&key=#{key}&language=en")
      data = fetch_json(url)
      return nil unless data && data["status"] == "OK" && data["results"].any?

      loc = data["results"].first["geometry"]["location"]
      [ loc["lat"], loc["lng"] ]
    rescue => e
      Rails.logger.warn("Google text geocoding error: #{redact_key(e.message)}")
      nil
    end

    def geocode_text_nominatim(str)
      query = str.to_s.strip
      return nil if query.blank?

      uri = URI("https://nominatim.openstreetmap.org/search" \
                "?format=json&limit=1&q=#{URI.encode_www_form_component(query)}")
      data = with_nominatim_rate_limit do
        fetch_json(
          uri,
          headers: { "User-Agent" => "GetCourt/1.0 (hello@getcourt.co)" },
          retries: 3
        )
      end
      result = Array(data).first
      return nil unless result&.dig("lat") && result&.dig("lon")

      [ Float(result["lat"]), Float(result["lon"]) ]
    rescue => e
      Rails.logger.warn("Nominatim text geocoding error: #{e.message}")
      nil
    end

    def geocode_nominatim_structured(lat, lng)
      uri = URI("https://nominatim.openstreetmap.org/reverse" \
                "?format=json&lat=#{lat}&lon=#{lng}&accept-language=en")
      data = with_nominatim_rate_limit do
        fetch_json(
          uri,
          headers: { "User-Agent" => "GetCourt/1.0 (hello@getcourt.co)" },
          retries: 3
        )
      end
      return nil unless data

      addr           = data["address"]
      city_component = addr && %w[city town village municipality].find { |key| addr[key] }
      city_name      = city_component && addr[city_component]
      street         = addr && [ addr["road"], addr["house_number"] ].compact.join(" ").presence
      country_code   = normalize_country_code(addr && addr["country_code"])
      { address: data["display_name"], city_name: city_name, street: street,
        country_code: country_code, city_component: city_component }
    rescue => e
      Rails.logger.warn("Nominatim error: #{e.message}")
      nil
    end

    def with_nominatim_rate_limit
      self.class::NOMINATIM_MUTEX.synchronize do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        wait = 1.0 - (now - self.class.nominatim_last_request_at)
        sleep(wait) if wait.positive?
        self.class.nominatim_last_request_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        yield
      end
    end

    def fetch_json(uri, headers: {}, retries: 1)
      uri = URI(uri) unless uri.is_a?(URI)
      tries = 0
      begin
        tries += 1
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = (uri.scheme == "https")
        http.open_timeout = 5
        http.read_timeout = 10
        req = Net::HTTP::Get.new(uri)
        headers.each { |k, v| req[k] = v }
        res = http.request(req)
        return JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)
        nil
      rescue Net::ReadTimeout, Net::OpenTimeout => e
        retry if tries < retries
        Rails.logger.warn("HTTP timeout for #{loggable_uri(uri)}: #{e.class}")
        nil
      rescue => e
        Rails.logger.warn("HTTP error for #{loggable_uri(uri)}: #{e.class} #{redact_key(e.message)}")
        nil
      end
    end

    # Query в лог не пишем: в нём ключ Google (key=…) и адрес, который искали.
    def loggable_uri(uri)
      "#{uri.scheme}://#{uri.host}#{uri.path}"
    end

    # Текст исключения может нести URL целиком — ключ в нём маскируем.
    def redact_key(text)
      text.to_s.gsub(/key=[^&\s"]+/, "key=[FILTERED]")
    end

    def gcomp(components, *types, name: "long_name")
      gcomp_typed(components, *types, name: name).first
    end

    # Как gcomp, но вместе со значением отдаёт тип компонента, который сработал.
    def gcomp_typed(components, *types, name: "long_name")
      types.each do |t|
        v = components.find { |c| c["types"].include?(t) }&.dig(name)
        return [ v, t ] if v.present?
      end
      [ nil, nil ]
    end

    def normalize_country_code(value)
      Cities::Resolver.normalize_country_code(value)
    end
  end
end
