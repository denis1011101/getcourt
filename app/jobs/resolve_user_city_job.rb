class ResolveUserCityJob < ApplicationJob
  queue_as :default

  def perform(user_id, original_query)
    return if original_query.blank?

    user = User.find_by(id: user_id)
    return unless user

    coords_regex = /\A\s*-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?\s*\z/

    if original_query =~ coords_regex
      lat, lon = original_query.split(",").map { |s| s.to_f }
      city = find_city_by_coords(lat, lon)
    else
      city = Cities::SearchService.new(query: original_query, limit: 1).call.first rescue nil
    end

    return unless city

    new_name = city.canonical_name
    tz_to_set = city.rails_timezone

    # avoid clobbering if user changed city manually after save:
    expected_current = original_query =~ coords_regex ? original_query : translit_str(original_query)
    return unless user.city_name.to_s.strip == expected_current

    # collect attributes to update
    update_attrs = {}

    if original_query =~ coords_regex
      # if user submitted coords, replace coords with resolved city name and tz
      update_attrs[:city_name] = new_name if new_name.present? && user.city_name.to_s.strip != new_name
      update_attrs[:timezone] = tz_to_set if tz_to_set.present? && user.timezone.to_s.strip != tz_to_set
    else
      # for plain name input: do not overwrite user's city_name (we saved translit immediately)
      update_attrs[:timezone] = tz_to_set if tz_to_set.present? && user.timezone.to_s.strip != tz_to_set
    end

    if update_attrs.any?
      begin
        user.update(update_attrs)
        Rails.logger.info "[ResolveUserCityJob] updated User##{user.id} #{update_attrs.keys.join(',')}"
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
