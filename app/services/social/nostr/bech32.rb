module Social
  module Nostr
    # Ключ в настройках обычно копируют как nsec1..., а протоколу нужны сырые
    # 32 байта — отсюда декодер bech32 (BIP-173). Только чтение: кодировать нам
    # нечего.
    module Bech32
      CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l".freeze
      GENERATOR = [ 0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3 ].freeze

      class Error < StandardError; end

      class << self
        # -> [hrp, data_bytes]
        def decode(value)
          value = value.to_s.strip
          raise Error, "empty value" if value.empty?
          raise Error, "mixed case" if value != value.downcase && value != value.upcase

          value = value.downcase
          position = value.rindex("1")
          raise Error, "no separator" if position.nil? || position.zero? || position + 7 > value.length

          hrp = value[0...position]
          data = value[(position + 1)..].chars.map do |char|
            CHARSET.index(char) or raise Error, "invalid character #{char.inspect}"
          end
          raise Error, "bad checksum" unless polymod(expand(hrp) + data) == 1

          [ hrp, convert_bits(data[0..-7], 5, 8) ]
        end

        private

        def expand(hrp)
          hrp.bytes.map { |byte| byte >> 5 } + [ 0 ] + hrp.bytes.map { |byte| byte & 31 }
        end

        def polymod(values)
          checksum = 1

          values.each do |value|
            top = checksum >> 25
            checksum = ((checksum & 0x1ffffff) << 5) ^ value
            5.times { |index| checksum ^= top[index] == 1 ? GENERATOR[index] : 0 }
          end

          checksum
        end

        def convert_bits(values, from, to)
          accumulator = 0
          bits = 0
          result = []
          max = (1 << to) - 1

          values.each do |value|
            accumulator = (accumulator << from) | value
            bits += from

            while bits >= to
              bits -= to
              result << ((accumulator >> bits) & max)
            end
          end

          raise Error, "invalid padding" if bits >= from || ((accumulator << (to - bits)) & max) != 0

          result.pack("C*")
        end
      end
    end
  end
end
