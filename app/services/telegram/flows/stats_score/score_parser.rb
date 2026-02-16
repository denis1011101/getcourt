module Telegram
  module Flows
    module StatsScore
      module ScoreParser
        module_function

        def parse(text)
          raw = text.to_s.strip
          return nil if raw.empty?

          tokens = raw.split(/[\s,]+/).map(&:strip).reject(&:empty?)
          sets = []

          tokens.each do |tok|
            m = tok.match(/\A(\d{1,2})\s*[-:]\s*(\d{1,2})\z/)
            return nil unless m
            sets << [ m[1].to_i, m[2].to_i ]
          end

          return nil if sets.empty?

          a_sets = sets.count { |a, b| a > b }
          b_sets = sets.count { |a, b| b > a }

          normalized = sets.map { |a, b| "#{a}-#{b}" }.join(" ")

          result =
            if a_sets == b_sets
              :draw
            else
              a_sets > b_sets ? :a : :b
            end

          { normalized: normalized, result: result }
        end
      end
    end
  end
end
