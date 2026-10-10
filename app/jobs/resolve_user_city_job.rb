class ResolveUserCityJob < ApplicationJob
  queue_as :default

  COORDS_REGEX = /\A\s*-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?\s*\z/

  # Часовой пояс и город решаются раздельно. Пояс — как и раньше, по самому
  # населённому кандидату: промах в нём безобиден. city_id — только строгим
  # Cities::Resolver: кандидат для пояса основанием для связи не служит.
  def perform(user_id, original_query)
    return if original_query.blank?
    return unless User.exists?(id: user_id)

    coords = original_query.match?(COORDS_REGEX)

    if coords
      lat, lon = original_query.split(",").map { |s| s.to_f }
      timezone_city = find_city_by_coords(lat, lon)
      # Тот же геокодер, что у кортов, — с его лимитом частоты, таймаутами и
      # запасным Nominatim.
      location = Cities::Resolver.new.resolve_geocoded(Geocoding::AddressResolver.new.resolve(lat, lon))
    else
      timezone_city = Cities::SearchService.new(query: original_query, limit: 1).call.first rescue nil
      # Без страны годится только алиас, явно разрешённый без страны.
      location = Cities::Resolver.new.resolve_text(translit_str(original_query))
    end

    # Читаем пользователя после геокодера: пока тот отвечал, город могли
    # сменить, и тогда этот результат уже не про него.
    user = User.find_by(id: user_id)
    return unless user

    # avoid clobbering if user changed city manually after save:
    expected_current = coords ? original_query : translit_str(original_query)
    return unless user.city_name.to_s.strip == expected_current

    # collect attributes to update
    update_attrs = {}

    tz_to_set = timezone_city&.rails_timezone
    update_attrs[:timezone] = tz_to_set if tz_to_set.present? && user.timezone.to_s.strip != tz_to_set

    if coords
      # Название — как до связи со справочником: строго определённый город, а
      # если не вышло — ближайший кандидат (по нему же считаем пояс). Иначе в
      # профиле остались бы координаты, а сравнения по city_name не сработали.
      # city_id — только строгий: кандидат по близости основанием не служит.
      name_city = location.resolved? ? location.city : timezone_city
      new_name = name_city&.canonical_name
      update_attrs[:city_name] = new_name if new_name.present? && user.city_name.to_s.strip != new_name
      update_attrs[:city_id] = location.city.id if location.resolved?
    else
      # for plain name input: do not overwrite user's city_name (we saved translit immediately)
      update_attrs[:city_id] = location.city.id if location.resolved?
    end
    update_attrs.delete(:city_id) if update_attrs[:city_id] == user.city_id

    if update_attrs.any?
      begin
        user.update(update_attrs)
        Rails.logger.info "[ResolveUserCityJob] updated User##{user.id} #{update_attrs.keys.join(',')} (#{location.reason})"
      rescue => e
        Rails.logger.warn "[ResolveUserCityJob] failed to update User##{user.id}: #{e.message}"
      end
    end
  end

  private

  def translit_str(s)
    Russian.translit(s.to_s)
  end

  def find_city_by_coords(lat, lon)
    lat_col = City.column_names.include?("lat") ? "lat" : (City.column_names.include?("latitude") ? "latitude" : nil)
    lon_col = City.column_names.include?("lon") ? "lon" : (City.column_names.include?("longitude") ? "longitude" : nil)
    return nil unless lat_col && lon_col

    box_deg = 0.5
    min_lat = lat - box_deg
    max_lat = lat + box_deg
    min_lon = lon - box_deg
    max_lon = lon + box_deg

    distance_sql = "(#{lat_col} - #{lat})*(#{lat_col} - #{lat}) + (#{lon_col} - #{lon})*(#{lon_col} - #{lon})"

    relation = City.select(:id, :name, :country_code, :timezone, :population, lat_col, lon_col)
                   .where("#{lat_col} BETWEEN ? AND ? AND #{lon_col} BETWEEN ? AND ?", min_lat, max_lat, min_lon, max_lon)

    if relation.exists?
      candidates = relation.order(Arel.sql(distance_sql)).limit(10).to_a
      candidates.max_by { |c| (c.respond_to?(:population) && c.population.to_i) || 0 }
    else
      City.select(:id, :name, :country_code, :timezone, :population, lat_col, lon_col)
          .order(Arel.sql(distance_sql))
          .limit(1).first
    end
  end
end
