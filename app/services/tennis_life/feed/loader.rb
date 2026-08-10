module TennisLife
  module Feed
    class Loader
      Card = Struct.new(:kind, :id, :record, :meta, keyword_init: true)

      def initialize(slice, snapshot_ts:, player_rows: [])
        @slice = Array(slice)
        @snapshot_ts = snapshot_ts.in_time_zone
        @player_rows = Array(player_rows).index_by { |row| row[:user].id }
      end

      def load
        loaded = @slice.group_by(&:first).to_h do |kind, entries|
          ids = entries.map(&:last)
          [ kind, load_kind(kind, ids) ]
        end

        @slice.filter_map do |kind, id|
          payload = loaded.dig(kind, id)
          next unless payload

          record, meta = payload
          Card.new(kind: kind, id: id, record: record, meta: meta || {})
        end
      end

      private

      def load_kind(kind, ids)
        case kind
        when "telegram_post"
          index_records(TelegramPost.includes(:telegram_channel).where(id: ids))
        when "match"
          index_records(Match.includes(:user, :opponent, :game).where(id: ids))
        when "player"
          User.not_merged.includes(:player_statistic).where(id: ids).each_with_object({}) do |user, result|
            result[user.id] = [ user, @player_rows[user.id] || {} ]
          end
        when "upcoming_game", "urgent_search"
          index_records(Game.includes(:court, :user, :participations).where(id: ids))
        when "tournament"
          index_records(Tournament.includes(:user, :tournament_participants).where(id: ids))
        when "featured_match"
          index_records(::FeaturedMatch.includes(:court).where(id: ids))
        when "scoreboard"
          { "current" => [ TennisScoreboard::Fetcher.raw_text, {} ] }
        when "court_update"
          index_records(CourtSuggestion.includes(:court, :user).where(id: ids, status: "approved"))
        when "fact"
          Sources::Facts.resolve(ids, snapshot_ts: @snapshot_ts).transform_values { |fact| [ fact, {} ] }
        else
          {}
        end
      end

      def index_records(records)
        records.each_with_object({}) { |record, result| result[record.id] = [ record, {} ] }
      end
    end
  end
end
