module GamesHelper
  def weather_emoji(condition_type)
    Weather::Icons.for(condition_type)
  end

  def format_duration_minutes(minutes)
    minutes = minutes.to_i
    return "" if minutes <= 0

    hours = minutes / 60
    rest = minutes % 60
    parts = []
    parts << "#{hours}h" if hours > 0
    parts << "#{rest}m" if rest > 0
    parts.join(" ")
  end

  # Мини-фильтр «страна → город» над списком кортов в форме игры: справочник
  # стран, города каждой страны и город/страна каждого корта для JS.
  def court_picker_locations(courts)
    city_names = courts.filter_map { |court| court.city_name.presence }.uniq.sort
    city_country = city_country_map_for(city_names)

    cities_by_country = city_names.group_by { |name| city_country[name].to_s }
    countries = cities_by_country.keys.reject(&:blank?)
      .map { |code| [ country_name_for(code), code ] }.sort_by(&:first)

    {
      countries: countries,
      # Пустой ключ — «любая страна»: города без страны видны только там.
      cities_by_country: cities_by_country.merge("" => city_names),
      city_country: city_country
    }
  end

  # Город пользователя записан свободным текстом ("Ekaterinburg" против
  # "Yekaterinburg" у кортов), поэтому сравниваем нормализованные названия.
  def default_court_city(city_names, user)
    target = normalized_city(user&.city_name)
    return nil if target.blank?

    city_names.find { |name| normalized_city(name) == target }
  end
end
