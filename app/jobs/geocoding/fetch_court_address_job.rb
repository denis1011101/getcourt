class Geocoding::FetchCourtAddressJob < ApplicationJob
  queue_as :default

  require 'net/http'
  require 'uri'
  require 'json'

  def perform(court_id, lat = nil, lng = nil)
    court = Court.find_by(id: court_id)
    return unless court

    lat, lng = court.coordinates_pair unless lat && lng
    return unless lat && lng && !(lat.zero? && lng.zero?)

    cache_key = "addr:#{lat},#{lng}"

    # try Google first, then Nominatim via resilient HTTP call
    value = court.send(:geocode_google, lat, lng)
    value ||= geocode_nominatim_http(lat, lng)

    if value.present?
      Rails.cache.write(cache_key, value, expires_in: 1.day)
      Rails.logger.info "[Geocoding] cached address for Court##{court.id} -> #{value}"
    else
      Rails.logger.warn "[Geocoding] no address resolved for Court##{court.id}"
    end
  rescue => e
    Rails.logger.warn "[Geocoding] FetchCourtAddressJob failed for Court##{court_id}: #{e.class} #{e.message}"
  end

  private

  def geocode_nominatim_http(lat, lng)
    uri = URI.parse("https://nominatim.openstreetmap.org/reverse?format=json&lat=#{lat}&lon=#{lng}&accept-language=en")
    req = Net::HTTP::Get.new(uri)
    req['User-Agent'] = "GetCourt/1.0 (denisdenis9331@gmail.com)"
    res = nil
    tries = 0

    begin
      tries += 1
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 10, open_timeout: 5) do |http|
        res = http.request(req)
      end
    rescue Net::ReadTimeout, Net::OpenTimeout => e
      retry if tries < 3
      Rails.logger.warn "[Geocoding] Nominatim timeout: #{e.class}: #{e.message}"
      return nil
    end

    return nil unless res&.is_a?(Net::HTTPSuccess)
    data = JSON.parse(res.body) rescue nil
    data && data['display_name']
  end
end
