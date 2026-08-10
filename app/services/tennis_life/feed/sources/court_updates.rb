module TennisLife
  module Feed
    module Sources
      class CourtUpdates < Base
        def ids
          snapshotted(CourtSuggestion)
            .where(status: "approved", reviewed_at: ..snapshot_ts)
            .pluck(:id)
        end

        def weight
          0.5
        end
      end
    end
  end
end
