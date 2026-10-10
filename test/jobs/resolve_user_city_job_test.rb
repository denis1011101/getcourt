require "test_helper"

class ResolveUserCityJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include CacheHelper

  setup do
    @user = User.create!(email: "city_job_#{SecureRandom.hex(4)}@example.com", telegram_chat_id: rand(10**9..10**10))
  end

  # --- Текст из Телеграма (страны нет) -----------------------------------------

  test "Telegram input Москва keeps city_id empty when the only Moskva is Tajik" do
    moskva_tj = city!("Moskva", "TJ", 1220988, timezone: "Asia/Dushanbe", population: 4_000)

    reply_city_in_telegram("Москва")

    @user.reload
    assert_equal "Moskva", @user.city_name
    assert_nil @user.city_id, "без явного выбора или global-алиаса связи нет"
    # Пояс — по-прежнему от первого результата поиска по населению.
    assert_equal moskva_tj.rails_timezone, @user.timezone
  end

  test "Telegram input resolves through an explicitly global alias" do
    yekaterinburg = city!("Yekaterinburg", "RU", 1486209, timezone: "Asia/Yekaterinburg", population: 1_495_066)

    reply_city_in_telegram("Екатеринбург")

    @user.reload
    assert_equal "Ekaterinburg", @user.city_name, "текстовый ввод не переименовываем"
    assert_equal yekaterinburg, @user.city
    assert_equal "Ekaterinburg", @user.timezone, "Rails-имя пояса Asia/Yekaterinburg"
  end

  test "a new Telegram input drops the previously picked city" do
    moscow = city!("Moscow", "RU", 524901, timezone: "Europe/Moscow", population: 10_381_222)
    @user.update!(city_name: "Moscow", city: moscow)

    reply_city_in_telegram("Moscow")

    @user.reload
    assert_equal "Moscow", @user.city_name
    assert_nil @user.city_id, "обычное совпадение без страны связи не даёт"
    assert_equal moscow.rails_timezone, @user.timezone
  end

  test "ambiguous text keeps city_id empty while the timezone still comes from the most populous match" do
    newport_gb = city!("Newport", "GB", 2641598, timezone: "Europe/London", population: 145_000)
    city!("Newport", "US", 5223593, timezone: "America/New_York", population: 24_000)
    @user.update!(city_name: "Newport")

    ResolveUserCityJob.perform_now(@user.id, "Newport")

    @user.reload
    assert_nil @user.city_id
    assert_equal newport_gb.rails_timezone, @user.timezone
  end

  # --- Координаты --------------------------------------------------------------

  test "coordinates resolve through reverse geocoding and get the city name" do
    moscow = city!("Moscow", "RU", 524901, timezone: "Europe/Moscow", population: 10_381_222,
                   latitude: 55.75204, longitude: 37.61781)
    @user.update!(city_name: "55.75,37.62", timezone: nil)

    with_geocoder(city_name: "Moscow", country_code: "RU", city_component: "locality") do
      ResolveUserCityJob.perform_now(@user.id, "55.75,37.62")
    end

    @user.reload
    assert_equal moscow, @user.city
    assert_equal "Moscow", @user.city_name
    assert_equal moscow_timezone, @user.timezone
  end

  test "unresolved coordinates get the nearby city name and timezone, but no city link" do
    # Самый населённый сосед — Москва, но геокодер назвал район: связь не ставим.
    city!("Moscow", "RU", 524901, timezone: "Europe/Moscow", population: 10_381_222,
          latitude: 55.75204, longitude: 37.61781)
    @user.update!(city_name: "55.89,37.44", timezone: nil)

    with_geocoder(city_name: "Khimki Urban District", country_code: "RU", city_component: "administrative_area_level_2") do
      ResolveUserCityJob.perform_now(@user.id, "55.89,37.44")
    end

    @user.reload
    assert_nil @user.city_id
    assert_equal "Moscow", @user.city_name
    assert_equal moscow_timezone, @user.timezone
  end

  test "coordinates without a geocoder answer get the nearby city name, but no city link" do
    city!("Moscow", "RU", 524901, timezone: "Europe/Moscow", population: 10_381_222,
          latitude: 55.75204, longitude: 37.61781)
    @user.update!(city_name: "55.75,37.62", timezone: nil)

    with_geocoder(nil) do
      ResolveUserCityJob.perform_now(@user.id, "55.75,37.62")
    end

    @user.reload
    assert_nil @user.city_id
    assert_equal "Moscow", @user.city_name
    assert_equal moscow_timezone, @user.timezone
  end

  # Ни ответа геокодера, ни города рядом в справочнике: заменить нечем —
  # координаты остаются, как и до PR.
  test "coordinates with no geocoder answer and no nearby city stay as they are" do
    @user.update!(city_name: "-60.0,-140.0", timezone: nil)

    with_geocoder(nil) do
      ResolveUserCityJob.perform_now(@user.id, "-60.0,-140.0")
    end

    @user.reload
    assert_nil @user.city_id
    assert_equal "-60.0,-140.0", @user.city_name
    assert_nil @user.timezone
  end

  # --- Запоздавшая job ---------------------------------------------------------

  test "a late job does not touch a city the user has changed since" do
    city!("Yekaterinburg", "RU", 1486209, timezone: "Asia/Yekaterinburg", population: 1_495_066)
    kurgan = city!("Kurgan", "RU", 1501321, timezone: "Asia/Yekaterinburg", population: 333_606)
    @user.update!(city_name: "Kurgan", city: kurgan, timezone: "Europe/Moscow")

    ResolveUserCityJob.perform_now(@user.id, "Екатеринбург")

    @user.reload
    assert_equal kurgan, @user.city
    assert_equal "Europe/Moscow", @user.timezone
  end

  test "a change made while the geocoder answers wins over the job" do
    city!("Moscow", "RU", 524901, timezone: "Europe/Moscow", population: 10_381_222,
          latitude: 55.75204, longitude: 37.61781)
    @user.update!(city_name: "55.75,37.62", timezone: nil)
    user_id = @user.id
    fake = Object.new
    fake.define_singleton_method(:resolve) do |*|
      User.find(user_id).update!(city_name: "Kurgan")
      { address: "x", city_name: "Moscow", country_code: "RU", city_component: "locality" }
    end

    stub_singleton(Geocoding::AddressResolver, :new, -> { fake }) do
      ResolveUserCityJob.perform_now(@user.id, "55.75,37.62")
    end

    @user.reload
    assert_equal "Kurgan", @user.city_name
    assert_nil @user.city_id
    assert_nil @user.timezone
  end

  private

  def reply_city_in_telegram(text)
    chat_id = @user.telegram_chat_id.to_s

    with_memory_cache do
      Rails.cache.write("tg:conv:#{chat_id}", { "field" => "city" })
      stub_singleton(Telegram::Api, :send_simple, ->(*) { }) do
        stub_singleton(Telegram::Handlers::ProfileHandler, :show_profile, ->(*) { }) do
          perform_enqueued_jobs(only: ResolveUserCityJob) do
            Telegram::Flows::Profile::FieldFlow.process_profile_field_reply(
              "chat" => { "id" => chat_id }, "text" => text
            )
          end
        end
      end
    end
  end

  def moscow_timezone
    City.find_by!(geoname_id: 524901).rails_timezone
  end

  def with_geocoder(result, &block)
    result = result&.merge(address: "somewhere")
    fake = Object.new
    fake.define_singleton_method(:resolve) { |*| result }
    stub_singleton(Geocoding::AddressResolver, :new, -> { fake }, &block)
  end

  def city!(name, country_code, geoname_id, timezone:, population:, latitude: nil, longitude: nil)
    City.create!(name: name, asciiname: name, country_code: country_code, geoname_id: geoname_id,
                 timezone: timezone, population: population, latitude: latitude, longitude: longitude)
  end
end
