module TennisLife
  module Feed
    class Builder
      CACHE_VERSION = 3
      # Куда встаёт ведущий турнир табло: третья карточка, чтобы табло было на
      # первом экране, а не на 32-й позиции, куда его отправляет интерливер с
      # одной-двумя карточками против сотен постов.
      PINNED_SCOREBOARD_POSITION = 2
      # Пользовательские фото и ролики тоже тонут: интерливер размазывает пару
      # карточек по сотням других. Свежие ставим на 4-е и 8-е места, новые выше.
      PINNED_MEDIA_POSITIONS = [ 3, 7 ].freeze
      PINNED_MEDIA_MAX_AGE = 7.days

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
        pin(Interleaver.new(queues, seed: seed).call)
      end

      # Закреплённые карточки вынимаем все разом и вставляем по возрастанию
      # позиций: иначе вставка одной сдвигает уже поставленную.
      def pin(order)
        pins = (lead_scoreboard_pins(order) + fresh_media_pins(order)).sort_by(&:first)
        return order if pins.empty?

        pinned = order - pins.map(&:last)
        pins.each { |position, entry| pinned.insert([ position, pinned.size ].min, entry) }
        pinned
      end

      def lead_scoreboard_pins(order)
        lead = TennisScoreboard::Board.at(snapshot_ts).lead or return []
        entry = [ "scoreboard", lead.slug ]
        order.include?(entry) ? [ [ PINNED_SCOREBOARD_POSITION, entry ] ] : []
      end

      def fresh_media_pins(order)
        ids = order.filter_map { |kind, id| id if kind == "game_media" }
        return [] if ids.empty?

        ::GameMedium
          .where(id: ids, created_at: (snapshot_ts - PINNED_MEDIA_MAX_AGE)..)
          .order(created_at: :desc, id: :desc)
          .limit(PINNED_MEDIA_POSITIONS.size)
          .pluck(:id)
          .zip(PINNED_MEDIA_POSITIONS)
          .map { |id, position| [ position, [ "game_media", id ] ] }
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
