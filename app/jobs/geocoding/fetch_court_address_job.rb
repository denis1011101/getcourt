class Geocoding::FetchCourtAddressJob < ApplicationJob
  queue_as :default

  def perform(court_id, lat = nil, lng = nil)
    court = Court.find_by(id: court_id)
    return unless court

    coordinates = court.coordinates
    current = court.coordinates_pair
    lat, lng = current unless lat && lng
    return unless lat && lng && !(lat.zero? && lng.zero?)

    cache_key = "addr:#{lat},#{lng}"
    result = Geocoding::AddressResolver.new.resolve(lat, lng)

    if result.is_a?(Hash) && result[:address].present?
      Rails.cache.write(cache_key, result[:address], expires_in: 1.day)

      # Страну и город пишем только парой из одного разрешения: city_id без
      # страны или со страной другого ответа и есть «чужой город».
      location = Cities::Resolver.new.resolve_geocoded(result)
      attributes = { country_code: location.country_code, city_id: location.city&.id }
      attributes[:city_name] = result[:city_name] if result[:city_name].present?
      # Улицу храним в базе: адрес живёт только в кэше, а список кортов должен
      # различать одноимённые площадки и без похода в геокодер.
      attributes[:street] = result[:street] if result[:street].present?

      # Пока геокодер отвечал, корт могли передвинуть: тогда ответ про старое
      # место, а новые координаты разберёт своя job. Сверяем в том же UPDATE.
      written = [ lat, lng ] == current &&
        Court.where(id: court.id, coordinates: coordinates).update_all(attributes) == 1

      if written
        Rails.logger.info "[Geocoding] cached address for Court##{court.id} -> #{result[:address]} (city: #{result[:city_name]}, street: #{result[:street]}, country: #{location.country_code}, city_id: #{location.city&.id}, #{location.reason})"
      else
        Rails.logger.info "[Geocoding] skipped stale result for Court##{court.id}: court moved from #{lat},#{lng} or was removed"
      end
    else
      Rails.logger.warn "[Geocoding] no address resolved for Court##{court.id}"
    end
  rescue => e
    Rails.logger.warn "[Geocoding] FetchCourtAddressJob failed for Court##{court_id}: #{e.class} #{e.message}"
  end
end
