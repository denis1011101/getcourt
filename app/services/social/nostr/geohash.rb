module Social
  module Nostr
    # Единственный из наших форматов, где гео живёт в самом событии: тег
    # ["g", "<geohash>"]. Кладём несколько префиксов разной длины — так клиенты
    # находят пост и на радиусе города, и на радиусе квартала.
    module Geohash
      BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz".freeze
      PRECISIONS = [ 4, 5, 6, 7 ].freeze

      class << self
        def encode(latitude, longitude, precision = 9)
          lat_range = [ -90.0, 90.0 ]
          lng_range = [ -180.0, 180.0 ]
          hash = +""
          bits = 0
          bit = 0
          even = true

          while hash.length < precision
            range = even ? lng_range : lat_range
            middle = (range[0] + range[1]) / 2
            value = even ? longitude : latitude

            if value > middle
              bits = (bits << 1) | 1
              range[0] = middle
            else
              bits <<= 1
              range[1] = middle
            end

            even = !even
            bit += 1

            if bit == 5
              hash << BASE32[bits]
              bits = 0
              bit = 0
            end
          end

          hash
        end

        # Префиксы от грубого к точному — по одному тегу на радиус.
        def prefixes(latitude, longitude, precisions = PRECISIONS)
          full = encode(latitude, longitude, precisions.max)
          precisions.sort.map { |precision| full[0, precision] }.uniq
        end
      end
    end
  end
end
