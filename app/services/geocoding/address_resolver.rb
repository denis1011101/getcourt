# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Geocoding
  class AddressResolver
    # Resolves lat/lng to { address: String, city_name: String | nil } or nil.
    # Tries Google first, falls back to Nominatim.
    def resolve(lat, lng)
      geocode_google_full(lat, lng) || geocode_nominatim_structured(lat, lng)
    end

    # Forward geocoding: text string -> [lat, lng] or nil.
    def self.geocode_text(str)
      new.send(:geocode_text_google, str)
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
      city    = gcomp(components, "locality", "postal_town", "administrative_area_level_2")
      country = gcomp(components, "country")

      street_line = [ street, number ].compact.join(" ").presence
      address = [ street_line, city, country ].compact.join(", ").presence

      { address: address, city_name: city }
    rescue => e
      Rails.logger.warn("Google geocoding error: #{e.message}")
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
      Rails.logger.warn("Google text geocoding error: #{e.message}")
      nil
    end

    def geocode_nominatim_structured(lat, lng)
      uri = URI("https://nominatim.openstreetmap.org/reverse" \
                "?format=json&lat=#{lat}&lon=#{lng}&accept-language=en")
      data = fetch_json(uri,
                        headers: { "User-Agent" => "GetCourt/1.0 (denisdenis9331@gmail.com)" },
                        retries: 3)
      return nil unless data

      addr      = data["address"]
      city_name = addr && (addr["city"] || addr["town"] || addr["village"] || addr["municipality"])
      { address: data["display_name"], city_name: city_name }
    rescue => e
      Rails.logger.warn("Nominatim error: #{e.message}")
      nil
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
        Rails.logger.warn("HTTP timeout for #{uri}: #{e.class}")
        nil
      rescue => e
        Rails.logger.warn("HTTP error for #{uri}: #{e.class} #{e.message}")
        nil
      end
    end

    def gcomp(components, *types)
      types.each do |t|
        v = components.find { |c| c["types"].include?(t) }&.dig("long_name")
        return v if v.present?
      end
      nil
    end
  end
end
