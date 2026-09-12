module TennisLife
  module Feed
    class Builder
      CACHE_VERSION = 2
      # Куда встаёт ведущий турнир табло: третья карточка, чтобы табло было на
      # первом экране, а не на 32-й позиции, куда его отправляет интерливер с
      # одной-двумя карточками против сотен постов.
      PINNED_SCOREBOARD_POSITION = 2

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
        Sources::GameMedia,
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
        pin_lead_scoreboard(Interleaver.new(queues, seed: seed).call)
      end

      def pin_lead_scoreboard(order)
        lead = TennisScoreboard::Board.at(snapshot_ts).lead or return order
        entry = [ "scoreboard", lead.slug ]
        index = order.index(entry) or return order

        order.dup.tap do |pinned|
          pinned.delete_at(index)
          pinned.insert([ PINNED_SCOREBOARD_POSITION, pinned.size ].min, entry)
        end
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
