module TennisLife
  module Feed
    module Sources
      class Facts < Base
        KEYS = %w[
          total_hours
          courts_cities
          longest_match
          popular_surface
          player_month
          new_players_month
          busiest_court
        ].freeze

        def ids
          KEYS
        end

        def weight
          2.0
        end

        def self.resolve(keys, snapshot_ts:)
          Array(keys).index_with do |key|
            Rails.cache.fetch(
              [ "tl_feed_fact", key, snapshot_ts.beginning_of_hour.to_i ],
              expires_in: 1.hour
            ) { calculate(key, snapshot_ts) }
          end
        end

        def self.calculate(key, snapshot_ts)
          case key
          when "total_hours"
            scope = PlayerStatistic.where(created_at: ..snapshot_ts)
            value = scope.sum(:singles_hours).to_f + scope.sum(:doubles_hours).to_f
            { key: key, value: value.round(1) }
          when "courts_cities"
            scope = Court.approved.where(created_at: ..snapshot_ts)
            cities = scope.where.not(city_name: [ nil, "" ]).pluck(:city_name).map { |city| city.strip.downcase }.uniq
            { key: key, courts: scope.count, cities: cities.size }
          when "longest_match"
            match = Match.where(created_at: ..snapshot_ts, played_at: Season.current_start..snapshot_ts)
              .where.not(score: [ nil, "" ])
              .to_a
              .max_by { |candidate| candidate.score.scan(/\d+/).sum(&:to_i) }
            { key: key, score: match&.score, games: match&.score.to_s.scan(/\d+/).sum(&:to_i) }
          when "popular_surface"
            surface, count = Match.where(created_at: ..snapshot_ts, played_at: Season.current_start..snapshot_ts)
              .where.not(surface: [ nil, "" ])
              .group(:surface)
              .count
              .max_by { |_, total| total } || [ nil, 0 ]
            { key: key, surface: surface, count: count }
          when "player_month"
            user_id, count = Match.where(created_at: ..snapshot_ts, played_at: (snapshot_ts - 30.days)..snapshot_ts)
              .group(:user_id)
              .count
              .max_by { |_, total| total } || [ nil, 0 ]
            user = User.not_merged.find_by(id: user_id)
            { key: key, player_id: user&.id, name: user&.name, count: count }
          when "new_players_month"
            count = User.not_merged.where(created_at: (snapshot_ts - 30.days)..snapshot_ts).count
            { key: key, count: count }
          when "busiest_court"
            court_id, count = Game.where(created_at: ..snapshot_ts, date: Season.current_start.to_date..snapshot_ts.to_date)
              .group(:court_id)
              .count
              .max_by { |_, total| total } || [ nil, 0 ]
            court = Court.approved.find_by(id: court_id)
            { key: key, court_id: court&.id, name: court&.name, count: count }
          else
            { key: key }
          end
        end
        private_class_method :calculate
      end
    end
  end
end
