require "test_helper"

class Social::Nostr::GeohashTest < ActiveSupport::TestCase
  test "encodes known coordinates" do
    assert_equal "9q8yyk8yt", Social::Nostr::Geohash.encode(37.7749, -122.4194, 9)
    assert_equal "gcpvj0d", Social::Nostr::Geohash.encode(51.5074, -0.1278, 7)
    assert_equal "ezs42", Social::Nostr::Geohash.encode(42.6, -5.6, 5)
  end

  test "prefixes go from coarse to precise and share the same head" do
    prefixes = Social::Nostr::Geohash.prefixes(56.8389, 60.6057)

    assert_equal [ 4, 5, 6, 7 ], prefixes.map(&:length)
    assert prefixes.each_cons(2).all? { |short, long| long.start_with?(short) }
  end
end
