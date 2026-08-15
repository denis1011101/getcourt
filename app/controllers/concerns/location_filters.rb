module LocationFilters
  extend ActiveSupport::Concern

  COUNTRY_NAMES = {
    "AD" => "Andorra",
    "AE" => "United Arab Emirates",
    "AI" => "Anguilla",
    "AL" => "Albania",
    "AM" => "Armenia",
    "AO" => "Angola",
    "AR" => "Argentina",
    "AT" => "Austria",
    "AU" => "Australia",
    "AW" => "Aruba",
    "BA" => "Bosnia and Herzegovina",
    "BB" => "Barbados",
    "BE" => "Belgium",
    "BG" => "Bulgaria",
    "BJ" => "Benin",
    "BO" => "Bolivia",
    "BR" => "Brazil",
    "BS" => "Bahamas",
    "BY" => "Belarus",
    "BZ" => "Belize",
    "CA" => "Canada",
    "CD" => "DR Congo",
    "CF" => "Central African Republic",
    "CG" => "Congo",
    "CH" => "Switzerland",
    "CL" => "Chile",
    "CM" => "Cameroon",
    "CN" => "China",
    "CO" => "Colombia",
    "CR" => "Costa Rica",
    "CU" => "Cuba",
    "CV" => "Cape Verde",
    "CW" => "Curaçao",
    "CZ" => "Czech Republic",
    "DE" => "Germany",
    "DK" => "Denmark",
    "DM" => "Dominica",
    "DO" => "Dominican Republic",
    "EC" => "Ecuador",
    "EE" => "Estonia",
    "EG" => "Egypt",
    "ES" => "Spain",
    "ET" => "Ethiopia",
    "FI" => "Finland",
    "FR" => "France",
    "GA" => "Gabon",
    "GB" => "United Kingdom",
    "GE" => "Georgia",
    "GH" => "Ghana",
    "GP" => "Guadeloupe",
    "GQ" => "Equatorial Guinea",
    "GR" => "Greece",
    "GT" => "Guatemala",
    "GY" => "Guyana",
    "HN" => "Honduras",
    "HR" => "Croatia",
    "HT" => "Haiti",
    "HU" => "Hungary",
    "ID" => "Indonesia",
    "IE" => "Ireland",
    "IL" => "Israel",
    "IN" => "India",
    "IT" => "Italy",
    "JM" => "Jamaica",
    "JP" => "Japan",
    "KE" => "Kenya",
    "KG" => "Kyrgyzstan",
    "KR" => "South Korea",
    "KZ" => "Kazakhstan",
    "LB" => "Lebanon",
    "LK" => "Sri Lanka",
    "LR" => "Liberia",
    "MA" => "Morocco",
    "MC" => "Monaco",
    "MD" => "Moldova",
    "MK" => "North Macedonia",
    "MT" => "Malta",
    "MX" => "Mexico",
    "MY" => "Malaysia",
    "MZ" => "Mozambique",
    "NA" => "Namibia",
    "NG" => "Nigeria",
    "NI" => "Nicaragua",
    "NL" => "Netherlands",
    "NO" => "Norway",
    "NP" => "Nepal",
    "NZ" => "New Zealand",
    "PA" => "Panama",
    "PE" => "Peru",
    "PG" => "Papua New Guinea",
    "PH" => "Philippines",
    "PK" => "Pakistan",
    "PL" => "Poland",
    "PR" => "Puerto Rico",
    "PT" => "Portugal",
    "PY" => "Paraguay",
    "QA" => "Qatar",
    "RS" => "Serbia",
    "RU" => "Russia",
    "SE" => "Sweden",
    "SG" => "Singapore",
    "SJ" => "Svalbard and Jan Mayen",
    "SK" => "Slovakia",
    "SL" => "Sierra Leone",
    "SO" => "Somalia",
    "SR" => "Suriname",
    "SS" => "South Sudan",
    "ST" => "Sao Tome and Principe",
    "SV" => "El Salvador",
    "TD" => "Chad",
    "TG" => "Togo",
    "TH" => "Thailand",
    "TN" => "Tunisia",
    "TR" => "Turkey",
    "TW" => "Taiwan",
    "TZ" => "Tanzania",
    "UA" => "Ukraine",
    "US" => "United States",
    "UY" => "Uruguay",
    "UZ" => "Uzbekistan",
    "VC" => "Saint Vincent and the Grenadines",
    "VE" => "Venezuela",
    "VU" => "Vanuatu",
    "XK" => "Kosovo",
    "ZA" => "South Africa",
    "ZW" => "Zimbabwe"
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

    @city_country_map = City.country_codes_for(city_names)
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
