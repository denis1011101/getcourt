module TennisLife
  module Feed
    class Interleaver
      def initialize(queues, seed:)
        rng = Random.new(Integer(seed))
        @queues = queues.filter_map do |kind, ids, weight|
          values = ids.uniq.sort_by(&:to_s).shuffle(random: rng)
          next if values.empty?

          {
            kind: kind.to_s,
            ids: values,
            weight: weight.to_f,
            emitted: 0,
            total: values.size
          }
        end
      end

      def call
        result = []

        until @queues.all? { |queue| queue[:ids].empty? }
          live = @queues.reject { |queue| queue[:ids].empty? }
          eligible = without_third_consecutive_kind(live, result)
          queue = eligible.min_by { |candidate| priority(candidate) }

          result << [ queue[:kind], queue[:ids].shift ]
          queue[:emitted] += 1
        end

        result
      end

      private

      def priority(queue)
        [
          (queue[:emitted] + 1.0) / (queue[:total] * queue[:weight]),
          queue[:kind]
        ]
      end

      def without_third_consecutive_kind(live, result)
        return live if live.one? || result.size < 2
        return live unless result[-1].first == result[-2].first

        alternatives = live.reject { |queue| queue[:kind] == result[-1].first }
        alternatives.presence || live
      end
    end
  end
end
