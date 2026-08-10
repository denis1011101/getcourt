module TennisLife
  module Feed
    module Sources
      class UrgentSearches < UpcomingGames
        def ids
          available_games.where(urgent_player_search: true).pluck(:id)
        end

        def weight
          3.0
        end
      end
    end
  end
end
