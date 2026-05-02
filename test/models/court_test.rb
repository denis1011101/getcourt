require "test_helper"

class CourtTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include CacheHelper
  test "is invalid without name" do
    court = Court.new(name: nil)

    assert_not court.valid?
    assert_includes court.errors[:name], "can't be blank"
  end

  test "approved scope returns only approved courts" do
    courts(:one).update!(moderation_status: "approved")
    courts(:two).update!(moderation_status: "pending")

    assert_includes Court.approved, courts(:one)
    assert_not_includes Court.approved, courts(:two)
  end

  test "formatted_contact builds label and value" do
    court = courts(:one)
    court.update!(contact_type: "telegram", contact_value: "@getcourt")

    assert_equal "Telegram", court.contact_label
    assert_equal "Telegram: @getcourt", court.formatted_contact
  end

  test "contact_links builds hrefs for multiple contacts" do
    court = Court.new(
      contact_type: "telegram",
      contact_value: "telegram: @getcourt\nwebsite: getcourt.co\nother: Front desk"
    )

    assert_equal [
      "https://t.me/getcourt",
      "https://getcourt.co",
      nil
    ], court.contact_links.map { |contact| contact[:href] }
    assert_equal [
      "Telegram: @getcourt",
      "Website: getcourt.co",
      "Other: Front desk"
    ], court.contact_links.map { |contact| contact[:formatted] }
  end

  test "contact_entries_for_form preserves parsed contacts and pads blanks" do
    court = Court.new(
      contact_type: "telegram",
      contact_value: "telegram: @getcourt\nviber: +79990001122"
    )

    assert_equal [
      { "contact_type" => "telegram", "contact_value" => "@getcourt" },
      { "contact_type" => "viber", "contact_value" => "+79990001122" },
      { "contact_type" => nil, "contact_value" => nil }
    ], court.contact_entries_for_form(3)
  end

  # ---------------------------------------------------------------------------
  # Geocoding delegation
  # ---------------------------------------------------------------------------

  test "parse_location delegates text to Geocoding::AddressResolver.geocode_text" do
    with_stubbed_singleton_method(Geocoding::AddressResolver, :geocode_text, ->(*) { [ 55.75, 37.62 ] }) do
      result = Court.parse_location("Moscow")
      assert_equal [ 55.75, 37.62 ], result
    end
  end

  test "parse_location parses raw lat,lng string without calling AddressResolver" do
    called = false
    with_stubbed_singleton_method(Geocoding::AddressResolver, :geocode_text, ->(*) { called = true; nil }) do
      result = Court.parse_location("55.75,37.62")
      assert_equal [ 55.75, 37.62 ], result
      assert_not called, "AddressResolver.geocode_text should not be called for coordinate strings"
    end
  end

  test "near uses Geocoding::AddressResolver.haversine_km for distance filtering" do
    close_court = courts(:one)
    close_court.update_columns(coordinates: "55.75,37.62", moderation_status: "approved")

    with_stubbed_singleton_method(Geocoding::AddressResolver, :haversine_km, ->(*) { 5.0 }) do
      result = Court.near("55.75,37.62", 10)
      assert_includes result, close_court
    end
  end

  test "address returns cached value without enqueueing job" do
    court = courts(:one)
    court.update_columns(coordinates: "55.75,37.62", moderation_status: "approved")

    with_memory_cache do
      Rails.cache.write("addr:55.75,37.62", "Cached Street, Moscow")

      assert_no_enqueued_jobs only: Geocoding::FetchCourtAddressJob do
        assert_equal "Cached Street, Moscow", court.address
      end
    end
  end

  test "address enqueues FetchCourtAddressJob and returns Unknown address on cache miss" do
    court = courts(:one)
    court.update_columns(coordinates: "55.75,37.62", moderation_status: "approved")
    # force re-evaluation by clearing memoized @address
    court.remove_instance_variable(:@address) if court.instance_variable_defined?(:@address)

    with_memory_cache do
      assert_enqueued_with(job: Geocoding::FetchCourtAddressJob) do
        result = court.address
        assert_equal "Unknown address", result
      end
    end
  end

  test "after_commit enqueues FetchCourtAddressJob when coordinates change" do
    court = courts(:one)
    assert_enqueued_with(job: Geocoding::FetchCourtAddressJob) do
      court.update!(coordinates: "55.00,37.00", moderation_status: "approved")
    end
  end

  test "free_only scope returns only free courts" do
    courts(:one).update!(free: true,  moderation_status: "approved")
    courts(:two).update!(free: false, moderation_status: "approved")

    assert_includes Court.free_only, courts(:one)
    assert_not_includes Court.free_only, courts(:two)
  end

  private

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
