module TennisLife
  module Feed
    module Sources
      class FeaturedMatch < Base
        def ids
          snapshotted(::FeaturedMatch.where(active: true)).pluck(:id)
        end

        def weight
          3.0
        end
      end
    end
  end
end
