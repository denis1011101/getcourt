module TennisLife
  module Feed
    module Sources
      class Tournaments < Base
        def ids
          # By the tournament's own dates: a bracket that ended in spring is not news.
          recent(snapshotted(Tournament), column: :start_date).pluck(:id)
        end

        def weight
          2.0
        end
      end
    end
  end
end
