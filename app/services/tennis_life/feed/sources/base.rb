module TennisLife
  module Feed
    module Sources
      class Base
        # A feed of news must not carry last season's posts: every source that reports
        # on something already past is capped at this age.
        MAX_AGE = 30.days

        attr_reader :snapshot_ts

        def initialize(snapshot_ts:, **)
          @snapshot_ts = snapshot_ts.in_time_zone
        end

        def ids
          raise NotImplementedError
        end

        def kind
          self.class.name.demodulize.underscore.singularize
        end

        def weight
          1.0
        end

        private

        def snapshotted(relation)
          relation.where(created_at: ..snapshot_ts)
        end

        # Each source passes the column that carries the date of the event itself —
        # played_at, reviewed_at, published_at. That is not created_at: importing an
        # old post today would give it a fresh created_at and look like news.
        # Only the lower bound belongs here; keeping the page stable is the job of
        # `snapshotted`, and the snapshot is floored to the hour, so an event dated
        # inside the current hour is still a record we already had.
        def recent(relation, column:)
          relation.where(column => cutoff..)
        end

        def cutoff
          snapshot_ts - MAX_AGE
        end
      end
    end
  end
end
