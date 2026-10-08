module Cities
  # Определяет запись справочника по уже извлечённым данным — без внешних
  # запросов. Ошибаться можно только в сторону «не определён»: чужой город
  # хуже пустой связи. Поэтому страну по названию не угадываем, а город не
  # выбираем ни по населению, ни по близости, ни по первому результату поиска.
  #
  # reason: :resolved, :no_country, :no_match, :ambiguous,
  # :unsupported_location_type.
  class Resolver
    Result = Data.define(:city, :country_code, :reason) do
      def resolved?
        reason == :resolved
      end
    end

    # Компоненты, которыми геокодер называет сам населённый пункт: Google —
    # locality и postal_town (так он пишет британские города), Nominatim —
    # city, town, village. administrative_area_level_2, municipality и прочее —
    # административные единицы, городом не подтверждённые.
    CITY_COMPONENTS = %w[locality postal_town city town village].freeze
    COUNTRY_CODE_FORMAT = /\A[A-Z]{2}\z/

    # Регистр (Unicode case folding), Unicode-нормализация и пробелы. Буквы не
    # транслитерируем: похожее написание ещё не доказывает, что город тот же.
    def self.normalize(value)
      value.to_s.unicode_normalize(:nfkc).downcase(:fold).gsub(/[[:space:]]+/, " ").strip.presence
    end

    def self.normalize_country_code(value)
      code = value.to_s.strip.upcase
      code if code.match?(COUNTRY_CODE_FORMAT)
    end

    def initialize(aliases: Aliases.default)
      @aliases = aliases
    end

    # Результат геокодинга (Geocoding::AddressResolver#resolve).
    def resolve_geocoded(result)
      result = result.to_h
      resolve(result[:city_name], country_code: result[:country_code], component: result[:city_component])
    end

    def resolve(name, country_code:, component:)
      country = self.class.normalize_country_code(country_code)
      return build(nil, nil, :no_country) unless country
      return build(nil, country, :unsupported_location_type) unless CITY_COMPONENTS.include?(component.to_s)

      key = self.class.normalize(name)
      return build(nil, country, :no_match) unless key

      entries = @aliases.entries_for(key, country_code: country)
      return from_aliases(entries, country) if entries.any?

      matches = exact_matches(key, country)
      return build(nil, country, :ambiguous) if matches.size > 1
      return build(nil, country, :no_match) if matches.empty?

      build(matches.first, country, :resolved)
    end

    # Текст без страны: годится только алиас, явно разрешённый без страны.
    # Совпадение с name/asciiname — даже единственное — не доказательство:
    # «Москва» → «Moskva» есть в справочнике только в Таджикистане.
    def resolve_text(name)
      key = self.class.normalize(name)
      entries = key ? @aliases.global_entries_for(key) : []
      return build(nil, nil, :no_country) if entries.empty?

      from_aliases(entries, nil)
    end

    private

    # Проверенный алиас решает за точное совпадение, поэтому при битой цели на
    # точное совпадение не откатываемся: в стране может найтись другой город
    # с этим названием, а алиас говорит, что имелся в виду не он.
    def from_aliases(entries, country)
      targets = entries.map { |entry| [ entry.geoname_id, entry.country_code ] }.uniq
      return build(nil, country, :ambiguous) if targets.size > 1

      geoname_id, target_country = targets.first
      city = City.find_by(geoname_id: geoname_id, country_code: target_country)
      unless city
        Rails.logger.warn "[Cities::Resolver] alias target missing or in another country: #{entries.first.label}"
        return build(nil, country, :no_match)
      end

      build(city, city.country_code, :resolved)
    end

    # SQLite lower() складывает только ASCII, поэтому SQL лишь отбирает
    # кандидатов (в том числе по asciiname через транслит ключа), а совпадение
    # подтверждаем той же нормализацией в Ruby.
    def exact_matches(key, country)
      keys = [ key, I18n.transliterate(key) ].uniq

      City.where(country_code: country)
          .where("lower(name) IN (:keys) OR lower(asciiname) IN (:keys)", keys: keys)
          .select { |city| [ city.name, city.asciiname ].any? { |value| self.class.normalize(value) == key } }
    end

    def build(city, country_code, reason)
      Result.new(city: city, country_code: country_code, reason: reason)
    end
  end
end
