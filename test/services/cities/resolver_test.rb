require "test_helper"

class Cities::ResolverTest < ActiveSupport::TestCase
  # --- Страна и тип компонента ------------------------------------------------

  test "without a reliable country the city stays unresolved" do
    city!("Basel", "CH", 2661604)

    [ nil, "", "CHE", "1" ].each do |country|
      result = resolver.resolve("Basel", country_code: country, component: "locality")
      assert_equal :no_country, result.reason
      assert_nil result.city
      assert_nil result.country_code
    end
  end

  test "a district or unconfirmed administrative unit is not a city" do
    city!("Şişli", "TR", 739549, asciiname: "Sisli")

    %w[administrative_area_level_2 municipality sublocality].each do |component|
      result = resolver.resolve("Şişli", country_code: "TR", component: component)
      assert_equal :unsupported_location_type, result.reason
      assert_nil result.city
      assert_equal "TR", result.country_code, "страна известна и без города"
    end
  end

  test "a district without its own directory record stays unresolved" do
    city!("Beijing", "CN", 1816670)
    city!("Kotō", "JP", 11209896, asciiname: "Koto")
    city!("Tokyo", "JP", 1850147)

    assert_unresolved :no_match, resolver.resolve("Chaoyang District", country_code: "CN", component: "city")
    # Kotō из справочника — другой город (Кумамото), а не район Токио.
    assert_unresolved :no_match, resolver.resolve("Koto City", country_code: "JP", component: "city")
    assert_unresolved :no_match, resolver.resolve("Fatih", country_code: "TR", component: "town")
  end

  # --- Точное совпадение внутри страны ----------------------------------------

  test "one exact match inside the country resolves" do
    london = city!("London", "GB", 2643743)
    city!("London", "CA", 6058560)
    city!("London", "US", 4119617)

    result = resolver.resolve("London", country_code: "gb", component: "postal_town")

    assert result.resolved?
    assert_equal london, result.city
    assert_equal "GB", result.country_code
  end

  test "namesakes in other countries are never picked" do
    belgrade = city!("Belgrade", "RS", 792680)
    city!("Belgrade", "BE", 2802359)
    city!("Belgrade", "US", 4957962)
    city!("Belgrade", "US", 5639364)

    assert_equal belgrade, resolver.resolve("Belgrade", country_code: "RS", component: "locality").city
    assert_unresolved :no_match, resolver.resolve("Belgrade", country_code: "HU", component: "locality")
  end

  test "several namesakes inside one country are ambiguous" do
    city!("Newport", "US", 5223593)
    city!("Newport", "US", 4302529)
    city!("Newport", "GB", 2641598)

    result = resolver.resolve("Newport", country_code: "US", component: "locality")

    assert_unresolved :ambiguous, result
    assert_equal "US", result.country_code
  end

  test "matching folds case, Unicode form and whitespace and checks asciiname" do
    bastad = city!("Båstad", "SE", 2723287, asciiname: "Bastad")
    orebro = city!("Örebro", "SE", 2686657, asciiname: "Orebro")

    [ "Båstad", "  BÅSTAD ", "Båstad", "Bastad", "Båstad " ].each do |variant|
      assert_equal bastad, resolver.resolve(variant, country_code: "SE", component: "locality").city, variant.inspect
    end
    # SQLite lower() не трогает «Ö», но совпадение всё равно находится.
    assert_equal orebro, resolver.resolve("örebro", country_code: "SE", component: "locality").city
  end

  test "transliteration alone does not prove identity" do
    city!("Moscow", "RU", 524901)

    assert_unresolved :no_match, resolver(aliases: []).resolve("Moskva", country_code: "RU", component: "city")
    assert_unresolved :no_match, resolver(aliases: []).resolve("Москва", country_code: "RU", component: "city")
  end

  # --- Тёзки из выгрузки -------------------------------------------------------

  test "Moskva in RU never resolves to the Tajik namesake" do
    city!("Moskva", "TJ", 1220988)

    # Правильной записи нет — результат неразрешённый, а не таджикская Moskva.
    assert_unresolved :no_match, resolver.resolve("Moskva", country_code: "RU", component: "city")
    assert_unresolved :no_match, resolver(aliases: []).resolve("Moskva", country_code: "RU", component: "city")

    moscow = city!("Moscow", "RU", 524901)
    assert_equal moscow, resolver.resolve("Moskva", country_code: "RU", component: "city").city
  end

  test "Roma in IT never resolves to a namesake from another country" do
    city!("Roma", "AU", 2151187)
    city!("Roma", "LS", 932151)
    city!("Roma", "RO", 668737)
    city!("Roma", "US", 8479429)

    assert_unresolved :no_match, resolver.resolve("Roma", country_code: "IT", component: "city")

    rome = city!("Rome", "IT", 3169070)
    city!("Rome", "US", 4219762)
    assert_equal rome, resolver.resolve("Roma", country_code: "IT", component: "city").city
  end

  # --- Алиасы ------------------------------------------------------------------

  test "a scoped alias works only inside its own country" do
    vienna = city!("Vienna", "AT", 2761369)
    city!("Vienna", "US", 4791160)

    assert_equal vienna, resolver.resolve("Wien", country_code: "AT", component: "city").city
    assert_unresolved :no_match, resolver.resolve("Wien", country_code: "US", component: "city")
    assert_unresolved :no_country, resolver.resolve_text("Wien")
  end

  test "the mixed-script Toshkent spelling is covered by its scoped alias only" do
    tashkent = city!("Tashkent", "UZ", 1512569)

    assert_equal tashkent, resolver.resolve("Тоshkent", country_code: "UZ", component: "city").city
    # Похожие буквы глобально не подменяем.
    assert_unresolved :no_match, resolver.resolve("Toshkent", country_code: "UZ", component: "city")
  end

  test "an alias with a missing or foreign target does not fall back to another city" do
    city!("Moskva", "RU", 999_001) # одноимённая деревня
    city!("Moscow", "TJ", 524901) # цель есть, но не в той стране

    assert_unresolved :no_match, resolver.resolve("Moskva", country_code: "RU", component: "city")
  end

  test "an alias spelling with several targets stays ambiguous" do
    city!("Twin", "XX", 1)
    city!("Twin", "XX", 2)
    aliases = [ alias_row("Dual", "XX", 1), alias_row("Dual", "XX", 2) ]

    assert_unresolved :ambiguous, resolver(aliases: aliases).resolve("Dual", country_code: "XX", component: "city")
  end

  test "text without a country resolves only through an explicitly global alias" do
    yekaterinburg = city!("Yekaterinburg", "RU", 1486209)
    city!("Omsk", "RU", 1496153)

    assert_equal yekaterinburg, resolver.resolve_text("Ekaterinburg").city
    assert_equal yekaterinburg, resolver.resolve_text("yekaterinburg").city
    assert_equal "RU", resolver.resolve_text("Ekaterinburg").country_code
    # Единственное совпадение по названию — ещё не доказательство.
    assert_unresolved :no_country, resolver.resolve_text("Omsk")
    assert_unresolved :no_country, resolver.resolve_text("")
  end

  test "a scoped alias does not become global by itself" do
    city!("Twin", "XX", 1)

    scoped = resolver(aliases: [ alias_row("Twinny", "XX", 1) ])
    global = resolver(aliases: [ alias_row("Twinny", "XX", 1, global: true) ])

    assert_unresolved :no_country, scoped.resolve_text("Twinny")
    assert global.resolve_text("Twinny").resolved?
  end

  test "resolve_geocoded reads the AddressResolver result" do
    tbilisi = city!("Tbilisi", "GE", 611717)

    result = resolver.resolve_geocoded(address: "x", city_name: "T'bilisi", country_code: "GE", city_component: "city")
    assert_equal tbilisi, result.city

    assert_unresolved :no_country, resolver.resolve_geocoded(nil)
  end

  private

  def resolver(aliases: nil)
    aliases.nil? ? Cities::Resolver.new : Cities::Resolver.new(aliases: Cities::Aliases.new(aliases))
  end

  def alias_row(name, country_code, geoname_id, global: false)
    { "name" => name, "country_code" => country_code, "geoname_id" => geoname_id, "city" => "Twin", "global" => global }
  end

  def city!(name, country_code, geoname_id, asciiname: name)
    City.create!(name: name, asciiname: asciiname, country_code: country_code, geoname_id: geoname_id,
                 timezone: "UTC", population: 1000)
  end

  def assert_unresolved(reason, result)
    assert_equal reason, result.reason
    assert_nil result.city
  end
end
