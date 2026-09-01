require "test_helper"

class Social::Nostr::Bech32Test < ActiveSupport::TestCase
  # NIP-19: приватный ключ и его nsec-представление.
  NSEC = "nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5".freeze
  HEX = "67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa".freeze

  test "decodes an nsec key into raw bytes" do
    hrp, key = Social::Nostr::Bech32.decode(NSEC)

    assert_equal "nsec", hrp
    assert_equal HEX, key.unpack1("H*")
  end

  test "rejects a corrupted checksum" do
    assert_raises(Social::Nostr::Bech32::Error) do
      Social::Nostr::Bech32.decode(NSEC.sub(/.\z/, "q"))
    end
  end
end
