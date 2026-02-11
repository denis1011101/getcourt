require "net/http"
require "json"
require "uri"

class Court < ApplicationRecord
  has_many :games, dependent: :destroy
  validates :name, presence: true
  belongs_to :user, optional: true

  # планируем асинхронное получение адреса при смене координат
  after_commit :enqueue_address_fetch, on: %i[create update], if: -> { saved_change_to_coordinates? }

  MODERATION_STATUSES = %w[pending approved rejected].freeze
  validates :moderation_status, inclusion: { in: MODERATION_STATUSES }
  CONTACT_TYPES = %w[phone whatsapp telegram viber other].freeze

  scope :approved, -> { where(moderation_status: "approved") }
  scope :visible_to, ->(user) { user&.admin? ? all : approved }

  def approved?
    moderation_status == "approved"
  end

  def pending?
    moderation_status == "pending"
  end

  def contact_label
    contact_type.present? ? contact_type.capitalize : nil
  end

  def formatted_contact
    return nil if contact_value.blank?

    contact_label ? "#{contact_label}: #{contact_value}" : contact_value
  end

  def self.near(location, radius_km = 10)
    loc = parse_pair(location)
    return none unless loc
    lat, lon = loc

    all.select do |court|
      cloc = court.coordinates_pair
      next false unless cloc
      clat, clon = cloc
      haversine_km(lat, lon, clat, clon) <= radius_km
    end
  end

  def self.parse_location(str)
    str = str.to_s.strip
    return nil if str.empty?

    if str.match?(/\A-?\d+(\.\d+)?,\s*-?\d+(\.\d+)?\z/)
      parts = str.split(',').map { |s| (Float(s.strip) rescue nil) }
      return nil if parts.any?(&:nil?)
      return parts
    end

    geocode_text_google(str)
  end

  def self.haversine_km(lat1, lon1, lat2, lon2)
    rad = Math::PI / 180
    dlat = (lat2 - lat1) * rad
    dlon = (lon2 - lon1) * rad
    a = Math.sin(dlat / 2)**2 + Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dlon / 2)**2
    6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  end

  def address
    return @address if defined?(@address) && @address

    lat, lng = coordinates_pair
    return "Unknown address" unless lat && lng
    return "Unknown address" if lat.zero? && lng.zero?

    cache_key = "addr:#{lat},#{lng}"
    cached = Rails.cache.read(cache_key)
    if cached.present?
      @address = cached
    else
      # не делаем блокирующих сетевых вызовов в рендере — планируем background job
      enqueue_address_fetch
      @address = "Unknown address"
    end
  rescue => e
    Rails.logger.warn("Geocoding failed: #{e.class} #{e.message}")
    @address = "Geocoding error"
  end

  def coordinates_pair
    self.class.parse_pair(coordinates)
  end

  private

  def enqueue_address_fetch
    Geocoding::FetchCourtAddressJob.perform_later(id)
  end

  def geocode_google(lat, lng)
    result = geocode_google_full(lat, lng)
    result&.dig(:address)
  end

  # Returns { address: "Street, City, Country", city_name: "City" }
  def geocode_google_full(lat, lng)
    key = ENV["GOOGLE_GEOCODING_API_KEY"]
    return nil if key.to_s.strip.empty?

    url = URI("https://maps.googleapis.com/maps/api/geocode/json?latlng=#{lat},#{lng}&key=#{key}&language=en")
    data = fetch_json(url)
    return nil unless data && data["status"] == "OK" && data["results"].any?

    components = data["results"].first["address_components"]
    street  = gcomp(components, "route")
    number  = gcomp(components, "street_number")
    city    = gcomp(components, "locality", "postal_town", "administrative_area_level_2")
    country = gcomp(components, "country")

    street_line = [street, number].compact.join(" ").presence
    address = [street_line, city, country].compact.join(", ").presence

    { address: address, city_name: city }
  rescue => e
    Rails.logger.warn("Google geocoding error: #{e.message} (status=#{data&.dig('status')} msg=#{data&.dig('error_message')})")
    nil
  end

  def self.geocode_text_google(str)
    key = ENV["GOOGLE_GEOCODING_API_KEY"]
    return nil if key.to_s.strip.empty?

    url = URI("https://maps.googleapis.com/maps/api/geocode/json?address=#{URI.encode_www_form_component(str)}&key=#{key}&language=en")
    data = fetch_json(url)
    return nil unless data && data["status"] == "OK" && data["results"].any?

    loc = data["results"].first["geometry"]["location"]
    [loc["lat"], loc["lng"]]
  rescue => e
    Rails.logger.warn("Google text geocoding error: #{e.message} (status=#{data&.dig('status')} msg=#{data&.dig('error_message')})")
    nil
  end

  def geocode_nominatim(lat, lng)
    url = URI("https://nominatim.openstreetmap.org/reverse?format=json&lat=#{lat}&lon=#{lng}&accept-language=en")
    data = fetch_json(url, headers: { "User-Agent" => "GetCourt/1.0 (dev)" })
    return nil unless data && data["address"]

    addr    = data["address"]
    street  = addr["road"] || addr["pedestrian"] || addr["footway"] || addr["path"]
    number  = addr["house_number"]
    city    = addr["city"] || addr["town"] || addr["village"] || addr["municipality"] || addr["county"]
    country = addr["country"]

    street_line = [street, number].compact.join(" ").presence
    [street_line, city, country].compact.join(", ").presence
  rescue => e
    Rails.logger.warn("Nominatim error: #{e.message}")
    nil
  end

  def gcomp(components, *types)
    types.each do |t|
      v = components.find { |c| c["types"].include?(t) }&.dig("long_name")
      return v if v.present?
    end
    nil
  end

  def fetch_json(uri, headers: {})
    uri = URI(uri) unless uri.is_a?(URI)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = 3
    http.read_timeout = 4

    req = Net::HTTP::Get.new(uri)
    headers.each { |k, v| req[k] = v }

    res = http.request(req)
    return JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)
    nil
  rescue => e
    Rails.logger.warn("HTTP error for #{uri}: #{e.class} #{e.message}")
    nil
  end

  def self.parse_pair(str)
    parts = str.to_s.split(",").map { |s| (Float(s) rescue nil) }
    return nil if parts.length < 2 || parts.any?(&:nil?)
    [parts[0], parts[1]]
  end
end
