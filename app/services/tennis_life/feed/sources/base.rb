module TennisLife
  module Feed
    module Sources
      class Base
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
      end
    end
  end
end
