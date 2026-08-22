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

  private

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
