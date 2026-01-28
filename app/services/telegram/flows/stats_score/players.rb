module Telegram
  module Flows
    module StatsScore
      module Players
        module_function

        def for_game(game)
          users = []
          users << game.user
          users.concat(game.participations.includes(:user).map(&:user))
          users.compact.uniq(&:id)
        rescue
          []
        end
      end
    end
  end
end
