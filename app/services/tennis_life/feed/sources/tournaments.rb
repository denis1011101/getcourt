module TennisLife
  module Feed
    module Sources
      class Tournaments < Base
        def ids
          snapshotted(Tournament).pluck(:id)
        end

        def weight
          2.0
        end
      end
    end
  end
end
