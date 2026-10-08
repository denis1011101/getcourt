module Cities
  # Проверенные написания городов из config/city_aliases.yml. Обычная запись
  # действует только внутри своей страны; без страны (текст из Телеграма)
  # применяются лишь записи с global: true. Одно написание с несколькими целями
  # не схлопывается в одну — Resolver увидит всех кандидатов и сочтёт случай
  # неоднозначным.
  class Aliases
    CONFIG_PATH = Rails.root.join("config/city_aliases.yml")

    Entry = Data.define(:name, :country_code, :geoname_id, :city, :global) do
      def label
        "#{name} (#{country_code}) → #{geoname_id} #{city}"
      end
    end

    def self.default
      @default ||= load_file(CONFIG_PATH)
    end

    def self.load_file(path)
      new(YAML.safe_load_file(path).fetch("aliases"))
    end

    attr_reader :entries

    def initialize(rows)
      @entries = Array(rows).map { |row| build_entry(row) }.freeze
      @scoped = @entries.group_by { |entry| [ entry.country_code, Resolver.normalize(entry.name) ] }
      @global = @entries.select(&:global).group_by { |entry| Resolver.normalize(entry.name) }
    end

    # key — уже нормализованное название (Resolver.normalize).
    def entries_for(key, country_code:)
      @scoped.fetch([ country_code, key ], [])
    end

    def global_entries_for(key)
      @global.fetch(key, [])
    end

    # Глобальные алиасы в терминах City.normalize_name — чтобы старое строковое
    # сравнение (Ekaterinburg против Yekaterinburg) работало как раньше.
    # Написание с разными целями сюда не попадает: свести его не к чему.
    def name_aliases
      @name_aliases ||= @entries.select(&:global)
        .group_by { |entry| City.fold_name(entry.name) }
        .each_with_object({}) do |(variant, group), map|
          targets = group.map { |entry| City.fold_name(entry.city) }.uniq
          # «?» — след I18n.transliterate на нелатинских буквах: такой ключ
          # совпал бы с любым другим нелатинским словом той же длины.
          next if targets.size != 1 || variant.blank? || variant.include?("?")
          map[variant] = targets.first unless variant == targets.first
        end.freeze
    end

    # Расхождения конфига со справочником: цели нет, она в другой стране или
    # называется иначе. Пустой массив — конфиг согласован с этой базой.
    def problems(cities = City.all)
      found = cities.where(geoname_id: @entries.map(&:geoname_id)).index_by(&:geoname_id)

      @entries.filter_map do |entry|
        city = found[entry.geoname_id]
        if city.nil?
          "#{entry.label}: цели нет в справочнике"
        elsif city.country_code != entry.country_code
          "#{entry.label}: цель в стране #{city.country_code}"
        elsif city.canonical_name != entry.city
          "#{entry.label}: цель называется #{city.canonical_name}"
        end
      end
    end

    private

    def build_entry(row)
      row = row.to_h.stringify_keys
      name = row["name"].to_s.strip
      country_code = row["country_code"].to_s
      geoname_id = row["geoname_id"]
      city = row["city"].to_s.strip

      unless name.present? && city.present? && country_code.match?(Resolver::COUNTRY_CODE_FORMAT) &&
             geoname_id.is_a?(Integer) && geoname_id.positive? && [ nil, true, false ].include?(row["global"])
        raise ArgumentError, "Invalid city alias: #{row.inspect}"
      end

      Entry.new(name: name, country_code: country_code, geoname_id: geoname_id, city: city, global: row["global"] == true)
    end
  end
end
