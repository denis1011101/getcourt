require "test_helper"

# Сквозная проверка определения города на натуральных данных, а не на
# выдуманных: справочник — настоящие строки выгрузки GeoNames cities1000 (её же
# импортирует rake import:geonames) вокруг каждой точки плюс тёзки из других
# стран, ответы геокодера — записанные ответы Nominatim. Подменяется только
# HTTP: разбор ответа, Cities::Resolver, алиасы и обе job — боевые.
#
# GEOCODING_LIVE=1 — вместо записей ходить в настоящий геокодер (и в Google,
# если задан ключ): так видно, не поменялись ли ответы.
class CityResolutionTest < ActiveSupport::TestCase
  LIVE = ENV["GEOCODING_LIVE"].present?

  # Центр города по GeoNames; slug — имя записи в
  # test/fixtures/files/geocoding/nominatim.
  POINTS = {
    "yekaterinburg" => { lat: 56.85733, lon: 60.61529, geoname_id: 1486209, country: "RU" },
    "kamensk_uralsky" => { lat: 56.40626, lon: 61.93347, geoname_id: 1504826, country: "RU" },
    "kurgan" => { lat: 55.44905, lon: 65.34344, geoname_id: 1501321, country: "RU" },
    "chelyabinsk" => { lat: 55.1611, lon: 61.42877, geoname_id: 1508291, country: "RU" },
    "moscow" => { lat: 55.75204, lon: 37.61781, geoname_id: 524901, country: "RU" },
    # Отдельный город у границы Москвы: самый населённый сосед — Москва, но
    # корт в Химках остаётся в Химках.
    "khimki" => { lat: 55.9001, lon: 37.42848, geoname_id: 550280, country: "RU" },
    "astana" => { lat: 51.1801, lon: 71.44598, geoname_id: 1526273, country: "KZ" },
    "yerevan" => { lat: 40.17765, lon: 44.5126, geoname_id: 616052, country: "AM" }
  }.freeze

  # Ввод в Телеграме: страны нет, связь даёт только global-алиас. «Москва» —
  # «Moskva», а Moskva в справочнике только таджикская: связи нет.
  TELEGRAM_INPUT = {
    "Екатеринбург" => 1486209,
    "Каменск-Уральский" => 1504826,
    "Курган" => 1501321,
    "Челябинск" => 1508291,
    "Астана" => 1526273,
    "Ереван" => 616052,
    "Москва" => nil
  }.freeze

  setup do
    load_geonames_sample
  end

  POINTS.each do |slug, point|
    test "court at #{slug} gets its city and country from the geocoder" do
      court = Court.create!(name: "Court #{slug}", coordinates: "#{point[:lat]},#{point[:lon]}", moderation_status: "approved")

      with_recorded_geocoder do
        Geocoding::FetchCourtAddressJob.perform_now(court.id)
      end

      court.reload
      assert_equal point[:geoname_id], court.city&.geoname_id, "city for #{slug}: #{court.city_name.inspect}"
      assert_equal point[:country], court.country_code
      assert court.city_name.present?
    end

    test "user sharing coordinates at #{slug} gets the city, its name and a timezone" do
      user = User.create!(email: "coords-#{slug}@example.com")
      query = "#{point[:lat]},#{point[:lon]}"
      user.update!(city_name: query, timezone: nil)

      with_recorded_geocoder do
        ResolveUserCityJob.perform_now(user.id, query)
      end

      user.reload
      city = City.find_by!(geoname_id: point[:geoname_id])
      assert_equal city, user.city
      assert_equal city.canonical_name, user.city_name
      assert user.timezone.present?, "timezone for #{slug}"
    end
  end

  TELEGRAM_INPUT.each do |text, geoname_id|
    test "Telegram city #{text} #{geoname_id ? "links to #{geoname_id}" : "stays unlinked"}" do
      user = User.create!(email: "tg-#{geoname_id || "none"}-#{text.bytes.sum}@example.com")
      # Как Telegram-флоу: транслит в city_name сразу, связь — позже в job.
      user.update!(city_name: Russian.translit(text), city_id: nil)

      ResolveUserCityJob.perform_now(user.id, text)

      user.reload
      if geoname_id
        assert_equal geoname_id, user.city&.geoname_id
      else
        assert_nil user.city_id
      end
    end
  end

  private

  # Те же колонки, что читает rake import:geonames.
  def load_geonames_sample
    rows = file_fixture("geonames/cities1000_sample.txt").each_line.map do |line|
      fields = line.chomp.split("\t")
      { geoname_id: fields[0].to_i, name: fields[1], asciiname: fields[2], country_code: fields[8],
        latitude: fields[4], longitude: fields[5], population: fields[14].to_i, timezone: fields[17],
        created_at: Time.current, updated_at: Time.current }
    end
    City.insert_all(rows, unique_by: :geoname_id)
  end

  def with_recorded_geocoder(&block)
    return block.call if LIVE

    recordings = Pathname(file_fixture_path).join("geocoding/nominatim")
    resolver = Geocoding::AddressResolver.new
    resolver.define_singleton_method(:fetch_json) do |uri, **|
      uri = URI(uri)
      raise "unexpected request to #{uri.host}#{uri.path}" unless uri.host == "nominatim.openstreetmap.org" && uri.path == "/reverse"

      params = URI.decode_www_form(uri.query).to_h
      slug = POINTS.find { |_, point| point[:lat].to_s == params["lat"] && point[:lon].to_s == params["lon"] }&.first
      raise "no Nominatim recording for #{params["lat"]},#{params["lon"]}" unless slug

      JSON.parse(recordings.join("#{slug}.json").read)
    end

    # Записанным ответам ждать секунду между запросами незачем.
    Geocoding::AddressResolver.nominatim_last_request_at = -Float::INFINITY
    google_key = ENV.delete("GOOGLE_GEOCODING_API_KEY")
    stub_singleton(Geocoding::AddressResolver, :new, -> { resolver }, &block)
  ensure
    ENV["GOOGLE_GEOCODING_API_KEY"] = google_key if google_key
  end
end
