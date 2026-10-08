require "test_helper"

class Geocoding::FetchCourtAddressJobTest < ActiveSupport::TestCase
  include CacheHelper

  setup do
    @court = courts(:one)
    @court.update_columns(coordinates: "55.75,37.62", city_name: nil, moderation_status: "approved")
  end

  test "writes address to cache and updates city_name on success" do
    with_memory_cache do
      with_stubbed_resolver({ address: "Tverskaya St 1, Moscow, Russia", city_name: "Moscow" }) do
        Geocoding::FetchCourtAddressJob.new.perform(@court.id)

        assert_equal "Tverskaya St 1, Moscow, Russia", Rails.cache.read("addr:55.75,37.62")
        assert_equal "Moscow", @court.reload.city_name
      end
    end
  end

  test "stores the street so the court list can tell namesakes apart" do
    with_memory_cache do
      with_stubbed_resolver({ address: "Tverskaya St 1, Moscow, Russia", city_name: "Moscow", street: "Tverskaya St 1" }) do
        Geocoding::FetchCourtAddressJob.new.perform(@court.id)

        assert_equal "Tverskaya St 1", @court.reload.street
      end
    end
  end

  test "keeps the stored street when the resolver has none" do
    @court.update_columns(street: "Tverskaya St 1")

    with_memory_cache do
      with_stubbed_resolver({ address: "Somewhere, Moscow, Russia", city_name: "Moscow", street: nil }) do
        Geocoding::FetchCourtAddressJob.new.perform(@court.id)

        assert_equal "Tverskaya St 1", @court.reload.street
      end
    end
  end

  test "does not write cache when resolver returns nil" do
    with_memory_cache do
      with_stubbed_resolver(nil) do
        Geocoding::FetchCourtAddressJob.new.perform(@court.id)

        assert_nil Rails.cache.read("addr:55.75,37.62")
        assert_nil @court.reload.city_name
      end
    end
  end

  test "returns early when court is not found" do
    assert_nothing_raised do
      Geocoding::FetchCourtAddressJob.new.perform(-1)
    end
  end

  test "returns early when coordinates are blank" do
    @court.update_columns(coordinates: nil)

    resolve_calls = []
    with_stubbed_resolver_spy(resolve_calls) do
      Geocoding::FetchCourtAddressJob.new.perform(@court.id)
    end

    assert_empty resolve_calls
  end

  test "does not update city_name when result has no city_name" do
    @court.update_columns(city_name: "Existing City")

    with_stubbed_resolver({ address: "Some Address", city_name: nil }) do
      Geocoding::FetchCourtAddressJob.new.perform(@court.id)
      assert_equal "Existing City", @court.reload.city_name
    end
  end

  # --- Страна и город справочника ----------------------------------------------

  test "writes the resolved city and its country together, keeping the geocoder's city_name" do
    moscow = City.create!(name: "Moscow", asciiname: "Moscow", country_code: "RU", geoname_id: 524901)

    with_stubbed_resolver(moskva_result) do
      Geocoding::FetchCourtAddressJob.new.perform(@court.id)
    end

    @court.reload
    assert_equal moscow, @court.city
    assert_equal "RU", @court.country_code
    assert_equal "Moskva", @court.city_name, "строковое представление не переименовываем"
    assert_equal "Tverskaya St 1", @court.street
  end

  test "keeps the country but no city when the name does not resolve" do
    City.create!(name: "Moskva", asciiname: "Moskva", country_code: "TJ", geoname_id: 1220988)

    with_stubbed_resolver(moskva_result) do
      Geocoding::FetchCourtAddressJob.new.perform(@court.id)
    end

    @court.reload
    assert_nil @court.city_id, "таджикская Moskva — чужой город"
    assert_equal "RU", @court.country_code
    assert_equal "Moskva", @court.city_name
  end

  test "a district keeps its city_name and gets no city" do
    City.create!(name: "Istanbul", asciiname: "Istanbul", country_code: "TR", geoname_id: 745044)
    result = { address: "Fatih, Istanbul", city_name: "Fatih", country_code: "TR", city_component: "administrative_area_level_2" }

    with_stubbed_resolver(result) do
      Geocoding::FetchCourtAddressJob.new.perform(@court.id)
    end

    @court.reload
    assert_equal "Fatih", @court.city_name
    assert_nil @court.city_id
    assert_equal "TR", @court.country_code
  end

  test "reprocessing is stable and creates neither cities nor aliases" do
    moscow = City.create!(name: "Moscow", asciiname: "Moscow", country_code: "RU", geoname_id: 524901)

    assert_no_difference -> { City.count } do
      2.times do
        with_stubbed_resolver(moskva_result) { Geocoding::FetchCourtAddressJob.new.perform(@court.id) }
      end
    end

    assert_equal [ moscow.id, "RU" ], @court.reload.values_at(:city_id, :country_code)
  end

  test "a stale job does not write its result over newer coordinates" do
    City.create!(name: "Moscow", asciiname: "Moscow", country_code: "RU", geoname_id: 524901)
    court_id = @court.id
    fake = Object.new
    # Пока геокодер отвечает, корт переносят в другое место.
    fake.define_singleton_method(:resolve) do |*|
      Court.find(court_id).update!(coordinates: "48.85,2.35")
      { address: "Tverskaya St 1, Moscow", city_name: "Moscow", street: "Tverskaya St 1", country_code: "RU", city_component: "locality" }
    end

    with_stubbed_singleton_method(Geocoding::AddressResolver, :new, -> { fake }) do
      Geocoding::FetchCourtAddressJob.new.perform(@court.id)
    end

    @court.reload
    assert_nil @court.city_id
    assert_nil @court.country_code
    assert_nil @court.city_name
    assert_nil @court.street
  end

  test "a job for coordinates the court no longer has writes nothing" do
    with_stubbed_resolver(moskva_result) do
      Geocoding::FetchCourtAddressJob.new.perform(@court.id, 48.85, 2.35)
    end

    assert_nil @court.reload.country_code
    assert_nil @court.city_name
  end

  private

  def moskva_result
    { address: "Tverskaya St 1, Moskva", city_name: "Moskva", street: "Tverskaya St 1",
      country_code: "RU", city_component: "city" }
  end

  def with_stubbed_resolver(return_value, &block)
    fake = Object.new
    fake.define_singleton_method(:resolve) { |*| return_value }
    with_stubbed_singleton_method(Geocoding::AddressResolver, :new, -> { fake }, &block)
  end

  def with_stubbed_resolver_spy(calls_array, &block)
    fake = Object.new
    fake.define_singleton_method(:resolve) { |*args| calls_array << args; nil }
    with_stubbed_singleton_method(Geocoding::AddressResolver, :new, -> { fake }, &block)
  end

  def with_stubbed_singleton_method(target, method_name, replacement)
    sc = target.singleton_class
    had = sc.method_defined?(method_name) || sc.private_method_defined?(method_name)
    orig = sc.instance_method(method_name) if had
    callable = replacement.respond_to?(:call) ? replacement : ->(*) { replacement }
    sc.define_method(method_name) { |*a, **kw, &b| callable.call(*a, **kw, &b) }
    yield
  ensure
    had ? sc.define_method(method_name, orig) : sc.remove_method(method_name)
  end
end
