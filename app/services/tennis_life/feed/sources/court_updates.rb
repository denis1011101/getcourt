module TennisLife
  module Feed
    module Sources
      class CourtUpdates < Base
        def ids
          recent(snapshotted(CourtSuggestion), column: :reviewed_at)
            .where(status: "approved")
            .pluck(:id)
        end

        def weight
          0.5
        end
      end
    end
  end
end
