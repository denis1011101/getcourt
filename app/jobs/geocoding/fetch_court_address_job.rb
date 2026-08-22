class Geocoding::FetchCourtAddressJob < ApplicationJob
  queue_as :default

  def perform(court_id, lat = nil, lng = nil)
    court = Court.find_by(id: court_id)
    return unless court

    lat, lng = court.coordinates_pair unless lat && lng
    return unless lat && lng && !(lat.zero? && lng.zero?)

    cache_key = "addr:#{lat},#{lng}"
    result = Geocoding::AddressResolver.new.resolve(lat, lng)

    if result.is_a?(Hash) && result[:address].present?
      Rails.cache.write(cache_key, result[:address], expires_in: 1.day)
      court.update_column(:city_name, result[:city_name]) if result[:city_name].present?
      # Улицу храним в базе: адрес живёт только в кэше, а список кортов должен
      # различать одноимённые площадки и без похода в геокодер.
      court.update_column(:street, result[:street]) if result[:street].present?
      Rails.logger.info "[Geocoding] cached address for Court##{court.id} -> #{result[:address]} (city: #{result[:city_name]}, street: #{result[:street]})"
    else
      Rails.logger.warn "[Geocoding] no address resolved for Court##{court.id}"
    end
  rescue => e
    Rails.logger.warn "[Geocoding] FetchCourtAddressJob failed for Court##{court_id}: #{e.class} #{e.message}"
  end
end
