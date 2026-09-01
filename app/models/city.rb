class City < ApplicationRecord
  scope :by_name, ->(q) { where("lower(name) LIKE ?", "%#{q.to_s.downcase}%") }

  # Города-тёзки встречаются в разных странах; берём самый населённый, как это
  # делает фильтр по локации на страницах игр и кортов.
  def self.country_codes_for(names)
    names = Array(names).map(&:to_s).reject(&:blank?).uniq
    return {} if names.empty?

    where(name: names)
      .pluck(:name, :country_code, :population)
      .group_by(&:first)
      .transform_values { |rows| rows.max_by { |(_, _, population)| population.to_i }[1] }
  end

  # Написания одного города, разошедшиеся по базе: у пользователей город долго
  # был свободным текстом, у кортов он приходит из геокодера. Ключ — вариант,
  # значение — то, к чему приводим.
  NAME_ALIASES = {
    "yekaterinburg" => "ekaterinburg"
  }.freeze

  # Единая нормализация названия города для сравнений. Живёт в модели, потому
  # что сравнивают города и контроллеры, и модели, и телеграм-хендлеры; пока
  # это лежало в концерне контроллеров, до него дотягивались не все, и часть
  # мест сравнивала сырой downcase — для «Ekaterinburg» против «Yekaterinburg»
  # это молчаливое «город не совпал».
  def self.normalize_name(value)
    name = I18n.transliterate(value.to_s).downcase.strip.gsub(/\s+/, " ")
    return nil if name.blank?

    NAME_ALIASES.fetch(name, name)
  end

  # Все написания, которые нормализуются в это же название, — нужны там, где
  # город ищут запросом по справочнику, а не сравнением в памяти.
  def self.alias_names_for(name)
    ([ name ] + NAME_ALIASES.select { |_variant, canonical| canonical == name }.keys).uniq
  end

  # Каноническое имя города для профиля и матчинга с courts.city_name: берём
  # name, а не asciiname — в кортах города записаны с диакритикой («Båstad»,
  # «Acapulco de Juárez»), и asciiname с ними бы не совпал.
  def canonical_name
    name.presence || asciiname.presence
  end

  # GeoNames отдаёт IANA-зону, а часть кода ждёт отображаемое имя Rails.
  # Возвращаем то, что Rails понимает, иначе — nil, чтобы не записать мусор.
  def rails_timezone
    zone = ActiveSupport::TimeZone.all.find { |z| z.tzinfo.name == timezone }
    return zone.name if zone

    timezone if ActiveSupport::TimeZone[timezone.to_s].present?
  end
end
