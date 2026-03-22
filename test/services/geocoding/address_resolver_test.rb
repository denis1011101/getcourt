require "test_helper"

class Geocoding::AddressResolverTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # haversine_km — pure math, no mocking needed
  # ---------------------------------------------------------------------------

  test "haversine_km returns ~111 km for 1 degree latitude difference at equator" do
    dist = Geocoding::AddressResolver.haversine_km(0, 0, 1, 0)
    assert_in_delta 111.0, dist, 1.0
  end

  test "haversine_km returns 0 for identical coords" do
    assert_equal 0.0, Geocoding::AddressResolver.haversine_km(55.75, 37.62, 55.75, 37.62)
  end

  # ---------------------------------------------------------------------------
  # resolve — Google success
  # ---------------------------------------------------------------------------

  test "resolve returns address hash from Google on success" do
    google_payload = {
      "status" => "OK",
      "results" => [
        {
          "address_components" => [
            { "types" => [ "route" ], "long_name" => "Tverskaya St" },
            { "types" => [ "street_number" ], "long_name" => "1" },
            { "types" => [ "locality" ], "long_name" => "Moscow" },
            { "types" => [ "country" ], "long_name" => "Russia" }
          ]
        }
      ]
    }

    with_env("GOOGLE_GEOCODING_API_KEY" => "test_key") do
      with_stubbed_fetch_json(google_payload) do |resolver|
        result = resolver.resolve(55.75, 37.62)
        assert_equal "Tverskaya St 1, Moscow, Russia", result[:address]
        assert_equal "Moscow", result[:city_name]
      end
    end
  end

  # ---------------------------------------------------------------------------
  # resolve — Google key missing → falls back to Nominatim
  # ---------------------------------------------------------------------------

  test "resolve falls back to Nominatim when Google key is absent" do
    nominatim_payload = {
      "display_name" => "Tverskaya St, Moscow, Russia",
      "address" => { "city" => "Moscow" }
    }

    with_env("GOOGLE_GEOCODING_API_KEY" => "") do
      with_stubbed_fetch_json(nominatim_payload) do |resolver|
        result = resolver.resolve(55.75, 37.62)
        assert_equal "Tverskaya St, Moscow, Russia", result[:address]
        assert_equal "Moscow", result[:city_name]
      end
    end
  end

  # ---------------------------------------------------------------------------
  # resolve — both providers fail → nil
  # ---------------------------------------------------------------------------

  test "resolve returns nil when both providers fail" do
    with_env("GOOGLE_GEOCODING_API_KEY" => "") do
      with_stubbed_fetch_json(nil) do |resolver|
        assert_nil resolver.resolve(55.75, 37.62)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # geocode_text
  # ---------------------------------------------------------------------------

  test "geocode_text returns nil when Google key is absent" do
    with_env("GOOGLE_GEOCODING_API_KEY" => "") do
      assert_nil Geocoding::AddressResolver.geocode_text("Moscow")
    end
  end

  test "geocode_text returns nil on non-OK Google status" do
    payload = { "status" => "ZERO_RESULTS", "results" => [] }

    with_env("GOOGLE_GEOCODING_API_KEY" => "test_key") do
      with_stubbed_fetch_json(payload) do |resolver|
        result = resolver.send(:geocode_text_google, "nonexistent place xyz")
        assert_nil result
      end
    end
  end

  test "geocode_text returns [lat, lng] on Google success" do
    google_payload = {
      "status" => "OK",
      "results" => [
        { "geometry" => { "location" => { "lat" => 55.75, "lng" => 37.62 } } }
      ]
    }

    with_env("GOOGLE_GEOCODING_API_KEY" => "test_key") do
      with_stubbed_fetch_json(google_payload) do |resolver|
        result = resolver.send(:geocode_text_google, "Moscow")
        assert_equal [ 55.75, 37.62 ], result
      end
    end
  end

  private

  def with_stubbed_fetch_json(return_value)
    resolver = Geocoding::AddressResolver.new
    resolver.define_singleton_method(:fetch_json) { |*| return_value }
    yield resolver
  end

  def with_env(vars)
    old = vars.keys.each_with_object({}) { |k, h| h[k] = ENV[k] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| v.nil? ? ENV.delete(k) : ENV.store(k, v) }
  end
end
