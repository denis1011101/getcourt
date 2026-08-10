module TennisLife
  module Feed
    module Sources
      class Scoreboard < Base
        def ids
          [ "current" ]
        end

        def weight
          2.5
        end
      end
    end
  end
end
