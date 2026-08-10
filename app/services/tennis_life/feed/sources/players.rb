module TennisLife
  module Feed
    module Sources
      class Players < Base
        def initialize(snapshot_ts:, excluded_ids: [])
          super(snapshot_ts: snapshot_ts)
          @excluded_ids = Array(excluded_ids).map(&:to_i)
        end

        def ids
          active_since = [ Season.current_start, snapshot_ts - TennisLifeController::ACTIVE_RATING_MONTHS.months ].max
          user_ids = snapshotted(Match)
            .where(played_at: active_since..snapshot_ts)
            .where.not(user_id: @excluded_ids)
            .distinct
            .pluck(:user_id)

          User.not_merged.where(id: user_ids).pluck(:id)
        end
      end
    end
  end
end
