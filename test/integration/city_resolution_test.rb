require "test_helper"

# Сквозная проверка определения города на натуральных данных, а не на
# выдуманных: справочник — настоящие строки выгрузки GeoNames cities1000 (её же
# импортирует rake import:geonames) вокруг каждой точки плюс тёзки из других
# стран, ответы геокодера — записанные ответы Google (с прода, 2026-10-10) и
# Nominatim. Подменяется только HTTP: разбор ответа, Cities::Resolver, алиасы и
# обе job — боевые.
#
# GEOCODING_LIVE=1 — вместо записей ходить в настоящие геокодеры (в Google —
# если задан GOOGLE_GEOCODING_API_KEY): так видно, не поменялись ли ответы.
class CityResolutionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include CacheHelper

  LIVE = ENV["GEOCODING_LIVE"].present?

  # Прод сначала спрашивает Google, Nominatim — запасной путь: проверяем оба.
  # Запрос — хост, путь и как достать из параметров координаты точки.
  PROVIDERS = {
    "google" => [ "maps.googleapis.com", "/maps/api/geocode/json", ->(params) { params["latlng"].split(",") } ],
    "nominatim" => [ "nominatim.openstreetmap.org", "/reverse", ->(params) { params.values_at("lat", "lon") } ]
  }.freeze

  # Центр города по GeoNames; slug — имя записи в
  # test/fixtures/files/geocoding/<provider>, timezone — пояс Rails.
  POINTS = {
    "yekaterinburg" => { lat: 56.85733, lon: 60.61529, geoname_id: 1486209, country: "RU", timezone: "Ekaterinburg" },
    "kamensk_uralsky" => { lat: 56.40626, lon: 61.93347, geoname_id: 1504826, country: "RU", timezone: "Ekaterinburg" },
    "kurgan" => { lat: 55.44905, lon: 65.34344, geoname_id: 1501321, country: "RU", timezone: "Ekaterinburg" },
    "chelyabinsk" => { lat: 55.1611, lon: 61.42877, geoname_id: 1508291, country: "RU", timezone: "Ekaterinburg" },
    "moscow" => { lat: 55.75204, lon: 37.61781, geoname_id: 524901, country: "RU", timezone: "Moscow" },
    # Отдельный город у границы Москвы: самый населённый сосед — Москва, но
    # корт в Химках остаётся в Химках.
    "khimki" => { lat: 55.9001, lon: 37.42848, geoname_id: 550280, country: "RU", timezone: "Moscow" },
    "astana" => { lat: 51.1801, lon: 71.44598, geoname_id: 1526273, country: "KZ", timezone: "Almaty" },
    "yerevan" => { lat: 40.17765, lon: 44.5126, geoname_id: 616052, country: "AM", timezone: "Yerevan" }
  }.freeze

  # Ввод в Телеграме: страны нет, связь даёт только global-алиас. «Москва» —
  # «Moskva», а Moskva в справочнике только таджикская: Москву и её пояс даёт
  # согласованное исключение Moskva → Moscow.
  TELEGRAM_INPUT = {
    "Екатеринбург" => 1486209,
    "Каменск-Уральский" => 1504826,
    "Курган" => 1501321,
    "Челябинск" => 1508291,
    "Астана" => 1526273,
    "Ереван" => 616052,
    "Москва" => 524901
  }.freeze

  setup do
    load_geonames_sample
  end

  PROVIDERS.each_key.to_a.product(POINTS.to_a).each do |provider, (slug, point)|
    test "court at #{slug} gets its city and country from #{provider}" do
      court = Court.create!(name: "Court #{slug}", coordinates: "#{point[:lat]},#{point[:lon]}", moderation_status: "approved")

      with_geocoder(provider) do
        Geocoding::FetchCourtAddressJob.perform_now(court.id)
      end

      court.reload
      assert_equal point[:geoname_id], court.city&.geoname_id, "city for #{slug}: #{court.city_name.inspect}"
      assert_equal point[:country], court.country_code
      assert court.city_name.present?
    end

    test "user sharing coordinates at #{slug} gets the city, its name and a timezone from #{provider}" do
      user = User.create!(email: "coords-#{provider}-#{slug}@example.com")
      query = "#{point[:lat]},#{point[:lon]}"
      user.update!(city_name: query, timezone: nil)

      with_geocoder(provider) do
        ResolveUserCityJob.perform_now(user.id, query)
      end

      user.reload
      city = City.find_by!(geoname_id: point[:geoname_id])
      assert_equal city, user.city
      assert_equal city.canonical_name, user.city_name
      assert_equal point[:timezone], user.timezone
    end
  end

  TELEGRAM_INPUT.each do |text, geoname_id|
    test "Telegram city #{text} #{geoname_id ? "links to #{geoname_id}" : "stays unlinked"}" do
      user = User.create!(email: "tg-#{geoname_id || "none"}-#{text.bytes.sum}@example.com", telegram_chat_id: rand(10**9..10**10))

      reply_in_telegram(user, text)

      user.reload
      assert_equal Russian.translit(text), user.city_name
      if geoname_id
        assert_equal geoname_id, user.city&.geoname_id
        assert_equal user.city.rails_timezone, user.timezone
      else
        assert_nil user.city_id
      end
    end
  end

  private

  # Ответ на «Изменить город» через тот же вход, что у вебхука: разбор
  # сообщения, сохранение профиля и поставленная им в очередь job.
  def reply_in_telegram(user, text)
    chat_id = user.telegram_chat_id.to_s

    with_memory_cache do
      Telegram::Helpers::Conversation.set(chat_id, { "flow" => "profile_field", "field" => "city" })
      stub_singleton(Telegram::Api, :send_simple, ->(*) { }) do
        stub_singleton(Telegram::Handlers::ProfileHandler, :show_profile, ->(*) { }) do
          perform_enqueued_jobs(only: ResolveUserCityJob) do
            assert Telegram::Processors::ReplyProcessor.process("chat" => { "id" => chat_id }, "text" => text)
          end
        end
      end
    end
  end

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

  # Только этот провайдер: у Google — ключ, у Nominatim — без ключа, как
  # запасной путь. Запрос к другому провайдеру — ошибка теста, а не фолбэк.
  def with_geocoder(provider, &block)
    saved_key = ENV["GOOGLE_GEOCODING_API_KEY"]
    if provider == "nominatim"
      ENV.delete("GOOGLE_GEOCODING_API_KEY")
    elsif !LIVE
      ENV["GOOGLE_GEOCODING_API_KEY"] = "recorded"
    elsif saved_key.blank?
      skip "GOOGLE_GEOCODING_API_KEY не задан"
    end
    return block.call if LIVE

    # Записанным ответам ждать секунду между запросами незачем.
    Geocoding::AddressResolver.nominatim_last_request_at = -Float::INFINITY
    resolver = recorded_resolver(provider)
    stub_singleton(Geocoding::AddressResolver, :new, -> { resolver }, &block)
  ensure
    saved_key ? ENV["GOOGLE_GEOCODING_API_KEY"] = saved_key : ENV.delete("GOOGLE_GEOCODING_API_KEY")
  end

  def recorded_resolver(provider)
    host, path, coordinates = PROVIDERS.fetch(provider)
    recordings = Pathname(file_fixture_path).join("geocoding", provider)

    resolver = Geocoding::AddressResolver.new
    resolver.define_singleton_method(:fetch_json) do |uri, **|
      uri = URI(uri)
      raise "unexpected request to #{uri.host}#{uri.path}" unless uri.host == host && uri.path == path

      lat, lon = coordinates.call(URI.decode_www_form(uri.query).to_h)
      slug = POINTS.find { |_, point| point[:lat].to_s == lat && point[:lon].to_s == lon }&.first
      raise "no #{provider} recording for #{lat},#{lon}" unless slug

      JSON.parse(recordings.join("#{slug}.json").read)
    end
    resolver
  end
end
