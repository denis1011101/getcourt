module TennisLife
  module Feed
    module Sources
      class UpcomingGames < Base
        def ids
          available_games.where(urgent_player_search: false).pluck(:id)
        end

        def weight
          1.5
        end

        private

        def available_games
          snapshotted(Game)
            .where("games.date >= ? OR games.recurring = ?", snapshot_ts.to_date, true)
            .left_joins(:participations)
            .group("games.id")
            .having("SUM(CASE WHEN participations.status = 'approved' THEN 1 ELSE 0 END) < games.players_count")
        end
      end
    end
  end
end
