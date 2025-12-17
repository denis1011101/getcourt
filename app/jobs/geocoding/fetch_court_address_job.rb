class Geocoding::FetchCourtAddressJob < ApplicationJob
  queue_as :default

  def perform(court_id, lat = nil, lng = nil)
    court = Court.find_by(id: court_id)
    return unless court

    lat, lng = court.coordinates_pair unless lat && lng
    return unless lat && lng && !(lat.zero? && lng.zero?)

    cache_key = "addr:#{lat},#{lng}"
    # Вызов приватных методов через send — выполняется в background-воркере
    value = court.send(:geocode_google, lat, lng) || court.send(:geocode_nominatim, lat, lng)
    if value.present?
      Rails.cache.write(cache_key, value, expires_in: 1.day)
      Rails.logger.info "[Geocoding] cached address for Court##{court.id} -> #{value}"
    else
      Rails.logger.warn "[Geocoding] no address resolved for Court##{court.id}"
    end
  rescue => e
    Rails.logger.warn "[Geocoding] FetchCourtAddressJob failed for Court##{court_id}: #{e.class} #{e.message}"
  end
end
