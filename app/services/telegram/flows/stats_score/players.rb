module Telegram
  module Flows
    module StatsScore
      module Players
        module_function

        def for_game(game)
          game.participations.where(status: :approved).includes(:user).map(&:user).compact.uniq(&:id)
        rescue
          []
        end
      end
    end
  end
end
