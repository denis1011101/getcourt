require "base64"

module TennisLife
  module Feed
    class Cursor
      MAX_SEED = (2**31) - 1
      MAX_OFFSET = 1_000_000
      MAX_AGE = 1.day
      FUTURE_TOLERANCE = 5.minutes

      attr_reader :seed, :snapshot_ts, :offset

      def self.start(seed:, snapshot_ts: Time.current)
        new(seed: seed, snapshot_ts: snapshot_ts, offset: 0)
      end

      def self.parse(value, now: Time.current)
        cursor = decode(value)
        return unless cursor

        return if cursor.snapshot_ts > now + FUTURE_TOLERANCE
        return if cursor.snapshot_ts < now - MAX_AGE

        cursor
      end

      def self.expired?(value, now: Time.current)
        cursor = decode(value)
        cursor.present? && cursor.snapshot_ts < now - MAX_AGE
      end

      def self.decode(value)
        return if value.blank?
        return if value.to_s.bytesize > 128

        decoded = Base64.urlsafe_decode64(value.to_s)
        match = decoded.match(/\A(\d{1,10}):(\d{1,20}):(\d{1,7})\z/)
        return unless match

        seed, timestamp, offset = match.captures.map { |part| Integer(part, 10) }
        snapshot_ts =
          if timestamp > 10_000_000_000
            Time.zone.at(Rational(timestamp, 1_000_000))
          else
            Time.zone.at(timestamp)
          end

        return unless seed.between?(0, MAX_SEED)
        return unless offset.between?(0, MAX_OFFSET)

        new(seed: seed, snapshot_ts: snapshot_ts, offset: offset)
      rescue ArgumentError, TypeError
        nil
      end
      private_class_method :decode

      def initialize(seed:, snapshot_ts:, offset:)
        @seed = Integer(seed)
        @snapshot_ts = snapshot_ts.in_time_zone
        @offset = Integer(offset)
      end

      def advance(amount)
        self.class.new(seed: seed, snapshot_ts: snapshot_ts, offset: offset + Integer(amount))
      end

      def to_param
        timestamp = (snapshot_ts.to_r * 1_000_000).to_i
        Base64.urlsafe_encode64("#{seed}:#{timestamp}:#{offset}", padding: false)
      end
    end
  end
end
