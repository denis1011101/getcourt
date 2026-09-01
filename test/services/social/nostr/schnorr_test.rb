require "test_helper"

class Social::Nostr::SchnorrTest < ActiveSupport::TestCase
  # Официальные тест-векторы BIP-340 (индексы 1 и 2 из reference-таблицы).
  VECTORS = [
    {
      secret_key: "B7E151628AED2A6ABF7158809CF4F3C762E7160F38B4DA56A784D9045190CFEF",
      public_key: "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659",
      aux: "0000000000000000000000000000000000000000000000000000000000000001",
      message: "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89",
      signature: "6896BD60EEAE296DB48A229FF71DFE071BDE413E6D43F917DC8DCF8C78DE33418906D11AC976ABCCB20B091292BFF4EA897EFCB639EA871CFA95F6DE339E4B0A"
    },
    {
      secret_key: "C90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B14E5C9",
      public_key: "DD308AFEC5777E13121FA72B9CC1B7CC0139715309B086C960E18FD969774EB8",
      aux: "C87AA53824B4D7AE2EB035A2B5BBBCCC080E76CDC6D1692C4B0B62D798E6D906",
      message: "7E2D58D8B3BCDF1ABADEC7829054F90DDA9805AAB56C77333024B9D0A508B75C",
      signature: "5831AAEED7B44BB74E5EAB94BA9D4294C49BCF2A60728D8B4C200F50DD313C1BAB745879A5AD954A72C45A91C3A51D3C7ADEA98D82F8481E0E1E03674A6F3FB7"
    }
  ].freeze

  test "reproduces the BIP-340 test vectors" do
    VECTORS.each do |vector|
      secret_key = hex(vector[:secret_key])
      message = hex(vector[:message])

      assert_equal vector[:public_key], Social::Nostr::Schnorr.public_key(secret_key).unpack1("H*").upcase
      assert_equal vector[:signature],
                   Social::Nostr::Schnorr.sign(message, secret_key, hex(vector[:aux])).unpack1("H*").upcase
      assert Social::Nostr::Schnorr.verify(message, hex(vector[:public_key]), hex(vector[:signature]))
    end
  end

  test "rejects a signature made for another message" do
    vector = VECTORS.first

    assert_not Social::Nostr::Schnorr.verify(
      hex("00" * 32), hex(vector[:public_key]), hex(vector[:signature])
    )
  end

  test "a random key round-trips through sign and verify" do
    secret_key = SecureRandom.bytes(32)
    message = OpenSSL::Digest::SHA256.digest("getcourt")

    signature = Social::Nostr::Schnorr.sign(message, secret_key)

    assert_equal 64, signature.bytesize
    assert Social::Nostr::Schnorr.verify(message, Social::Nostr::Schnorr.public_key(secret_key), signature)
  end

  test "refuses a key outside the curve order" do
    assert_raises(Social::Nostr::Schnorr::Error) do
      Social::Nostr::Schnorr.public_key("\x00".b * 32)
    end
  end

  private

  def hex(value)
    [ value ].pack("H*")
  end
end
