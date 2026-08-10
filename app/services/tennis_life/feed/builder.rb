module TennisLife
  module Feed
    class Builder
      CACHE_VERSION = 1

      SOURCE_CLASSES = [
        Sources::TelegramPosts,
        Sources::Matches,
        Sources::Players,
        Sources::UpcomingGames,
        Sources::UrgentSearches,
        Sources::Tournaments,
        Sources::FeaturedMatch,
        Sources::Scoreboard,
        Sources::CourtUpdates,
        Sources::Facts
      ].freeze

      attr_reader :seed, :snapshot_ts

      def initialize(seed:, snapshot_ts:, excluded_player_ids: [])
        @seed = Integer(seed)
        @snapshot_ts = snapshot_ts.in_time_zone
        @excluded_player_ids = Array(excluded_player_ids).map(&:to_i).uniq.sort
      end

      def ordered_ids
        Rails.cache.fetch(cache_key, expires_in: 30.minutes) { build_order }
      end

      private

      def cache_key
        timestamp = (snapshot_ts.to_r * 1_000_000).to_i
        [ "tl_feed", CACHE_VERSION, seed, timestamp, @excluded_player_ids.join("-") ]
      end

      def build_order
        queues = sources.map { |source| [ source.kind, source.ids, source.weight ] }
        Interleaver.new(queues, seed: seed).call
      end

      def sources
        SOURCE_CLASSES.map do |source_class|
          options = { snapshot_ts: snapshot_ts }
          options[:excluded_ids] = @excluded_player_ids if source_class == Sources::Players
          source_class.new(**options)
        end
      end
    end
  end
end
