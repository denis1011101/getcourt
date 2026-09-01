require "openssl"
require "securerandom"

module Social
  module Nostr
    # BIP-340 (Schnorr над secp256k1) чистым Ruby: подписей у нас единицы в день,
    # а нативный гем ради них тянуть в деплой не хочется. Проверяется на
    # официальных тест-векторах BIP-340.
    module Schnorr
      P = 2**256 - 2**32 - 977
      N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
      G = [
        0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798,
        0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8
      ].freeze

      class Error < StandardError; end

      class << self
        # x-only публичный ключ (32 байта) из приватного.
        def public_key(secret_key)
          point = point_mul(G, normalize_secret(secret_key))
          raise Error, "secret key yields point at infinity" unless point

          to_bytes(point[0])
        end

        # message — ровно 32 байта (у нас это sha256 сериализованного события).
        def sign(message, secret_key, aux = SecureRandom.bytes(32))
          raise Error, "message must be 32 bytes" unless message.bytesize == 32

          d0 = normalize_secret(secret_key)
          point = point_mul(G, d0)
          d = point[1].even? ? d0 : N - d0

          t = d ^ to_int(tagged_hash("BIP0340/aux", aux))
          nonce = tagged_hash("BIP0340/nonce", to_bytes(t) + to_bytes(point[0]) + message)
          k0 = to_int(nonce) % N
          raise Error, "invalid nonce" if k0.zero?

          r = point_mul(G, k0)
          k = r[1].even? ? k0 : N - k0
          e = challenge(to_bytes(r[0]), to_bytes(point[0]), message)

          to_bytes(r[0]) + to_bytes((k + e * d) % N)
        end

        def verify(message, public_key, signature)
          return false unless signature.bytesize == 64 && public_key.bytesize == 32

          point = lift_x(to_int(public_key))
          return false unless point

          r = to_int(signature[0, 32])
          s = to_int(signature[32, 32])
          return false if r >= P || s >= N

          e = challenge(signature[0, 32], public_key, message)
          candidate = point_add(point_mul(G, s), point_mul(point, N - e))
          return false if candidate.nil? || candidate[1].odd?

          candidate[0] == r
        end

        def tagged_hash(tag, message)
          digest = OpenSSL::Digest::SHA256.digest(tag)
          OpenSSL::Digest::SHA256.digest(digest + digest + message)
        end

        def to_bytes(value)
          [ value.to_s(16).rjust(64, "0") ].pack("H*")
        end

        def to_int(bytes)
          bytes.unpack1("H*").to_i(16)
        end

        private

        def challenge(r_bytes, pubkey_bytes, message)
          to_int(tagged_hash("BIP0340/challenge", r_bytes + pubkey_bytes + message)) % N
        end

        def normalize_secret(secret_key)
          value = secret_key.is_a?(Integer) ? secret_key : to_int(secret_key)
          raise Error, "secret key out of range" unless value.between?(1, N - 1)

          value
        end

        def lift_x(x)
          return nil if x.zero? || x >= P

          c = (x.pow(3, P) + 7) % P
          y = c.pow((P + 1) / 4, P)
          return nil unless y.pow(2, P) == c

          [ x, y.even? ? y : P - y ]
        end

        # Аффинные координаты: nil — точка на бесконечности.
        def point_add(a, b)
          return b if a.nil?
          return a if b.nil?

          x1, y1 = a
          x2, y2 = b
          return nil if x1 == x2 && y1 != y2

          lambda_value =
            if x1 == x2
              (3 * x1 * x1) % P * inverse(2 * y1) % P
            else
              (y2 - y1) % P * inverse(x2 - x1) % P
            end

          x3 = (lambda_value * lambda_value - x1 - x2) % P
          [ x3, (lambda_value * (x1 - x3) - y1) % P ]
        end

        def point_mul(point, scalar)
          result = nil
          addend = point

          while scalar.positive?
            result = point_add(result, addend) if scalar.odd?
            addend = point_add(addend, addend)
            scalar >>= 1
          end

          result
        end

        def inverse(value)
          (value % P).pow(P - 2, P)
        end
      end
    end
  end
end
