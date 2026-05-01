module LocationFilters
  extend ActiveSupport::Concern

  COUNTRY_NAMES = {
    "AE" => "United Arab Emirates",
    "AI" => "Anguilla",
    "AR" => "Argentina",
    "AT" => "Austria",
    "AU" => "Australia",
    "BE" => "Belgium",
    "BR" => "Brazil",
    "BY" => "Belarus",
    "CA" => "Canada",
    "CH" => "Switzerland",
    "CL" => "Chile",
    "CN" => "China",
    "CO" => "Colombia",
    "CR" => "Costa Rica",
    "CZ" => "Czech Republic",
    "DE" => "Germany",
    "EC" => "Ecuador",
    "ES" => "Spain",
    "FR" => "France",
    "GE" => "Georgia",
    "GB" => "United Kingdom",
    "HR" => "Croatia",
    "HT" => "Haiti",
    "HU" => "Hungary",
    "IN" => "India",
    "IT" => "Italy",
    "JP" => "Japan",
    "KR" => "South Korea",
    "LR" => "Liberia",
    "MA" => "Morocco",
    "MC" => "Monaco",
    "NL" => "Netherlands",
    "NO" => "Norway",
    "NZ" => "New Zealand",
    "PH" => "Philippines",
    "PK" => "Pakistan",
    "PT" => "Portugal",
    "QA" => "Qatar",
    "RS" => "Serbia",
    "RU" => "Russia",
    "SE" => "Sweden",
    "SG" => "Singapore",
    "SK" => "Slovakia",
    "TH" => "Thailand",
    "TR" => "Turkey",
    "US" => "United States",
    "UZ" => "Uzbekistan",
    "ZA" => "South Africa"
  }.freeze

  CITY_COUNTRY_OVERRIDES = {
    "Koto" => "JP"
  }.freeze

  CITY_ALIASES = {
    "yekaterinburg" => "ekaterinburg"
  }.freeze

  included do
    helper_method :country_name_for, :location_filter_labels, :country_cities_map_for_select
  end

  private

  def prepare_location_filters(city_names)
    city_names = Array(city_names).map(&:to_s).reject(&:blank?).uniq.sort

    @city_country_map = City.where(name: city_names)
      .pluck(:name, :country_code, :population)
      .group_by(&:first)
      .transform_values { |rows| rows.max_by { |(_, _, population)| population.to_i }[1] }
      .merge(CITY_COUNTRY_OVERRIDES.slice(*city_names))

    @country_names_by_code = @city_country_map.values.uniq.compact.sort.each_with_object({}) do |country_code, names|
      names[country_code] = country_name_for(country_code)
    end
    @countries = @country_names_by_code.map { |country_code, country_name| [ country_name, country_code ] }.sort_by(&:first)
    @cities = params[:country].present? ? cities_for_country(params[:country]) : city_names
  end

  def cities_for_country(country_code)
    @city_country_map.select { |_, code| code == country_code }.keys.sort
  end

  def country_name_for(country_code)
    COUNTRY_NAMES[country_code.to_s] || country_code.to_s
  end

  def location_filter_labels(country_code = params[:country], city_name = params[:city])
    labels = []
    labels << country_name_for(country_code) if country_code.present?
    labels << city_name if city_name.present?
    labels
  end

  def normalized_city(value)
    city = I18n.transliterate(value.to_s).downcase.strip.gsub(/\s+/, " ")
    return nil if city.blank?

    CITY_ALIASES.fetch(city, city)
  end

  def city_aliases_for(city_name)
    ([ city_name ] + CITY_ALIASES.select { |_alias, canonical| canonical == city_name }.keys).uniq
  end

  def country_cities_map_for_select
    grouped = @city_country_map.each_with_object({}) do |(city_name, country_code), memo|
      memo[country_code] ||= []
      memo[country_code] << city_name
    end

    grouped.transform_values!(&:sort)
    grouped.merge("" => @city_country_map.keys.sort)
  end
end
