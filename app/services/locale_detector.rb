class LocaleDetector
  COUNTRY_LOCALES = {
    "ru" => %w[RU BY KZ UA KG TJ UZ AM MD],
    "es" => %w[ES MX AR CO CL PE VE EC GT CU BO DO HN PY SV NI CR PR UY]
  }.freeze

  def self.call(request, cookies)
    new(request, cookies).call
  end

  def initialize(request, cookies)
    @request = request
    @cookies = cookies
  end

  def call
    subdomain_locale
      || cookie_locale
      || country_locale
      || accept_language_locale
      || default_locale
  end

  private

  attr_reader :request, :cookies

  def subdomain_locale
    locale = request.subdomains.first.to_s
    locale if available_locales.include?(locale)
  end

  def cookie_locale
    locale = cookies[:preferred_locale].to_s
    locale if available_locales.include?(locale)
  end

  def country_locale
    country = request.headers["CF-IPCountry"].to_s.upcase
    COUNTRY_LOCALES.each do |locale, countries|
      return locale if countries.include?(country)
    end

    nil
  end

  def accept_language_locale
    parsed_accept_language.find { |locale| available_locales.include?(locale) }
  end

  def parsed_accept_language
    request.headers["Accept-Language"].to_s.split(",").filter_map do |entry|
      tag, *params = entry.strip.split(";")
      locale = tag.to_s.split("-").first.to_s.downcase
      next if locale.blank?

      q = params.find { |param| param.strip.start_with?("q=") }&.split("=")&.last&.to_f || 1.0
      next if q <= 0

      [ locale, q ]
    end.sort_by { |(_locale, q)| -q }.map(&:first)
  end

  def available_locales
    I18n.available_locales.map(&:to_s)
  end

  def default_locale
    I18n.default_locale.to_s
  end
end
