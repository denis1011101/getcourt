module Telegram
  module Flows
    module StatsScore
      module MatchUpserter
        module_function

        def call(game:, actor:, mode:, team_a_ids:, team_b_ids:, result:, played_at:, score:, force_new: false)
          team_a_ids = team_a_ids.map(&:to_i)
          team_b_ids = team_b_ids.map(&:to_i)

          all_ids = (team_a_ids + team_b_ids).uniq
          users = User.where(id: all_ids).to_a
          by_id = users.index_by(&:id)

          outcome_for_a = case result
          when :a then "win"
          when :b then "loss"
          else "draw"
          end

          outcome_for_b = case result
          when :a then "loss"
          when :b then "win"
          else "draw"
          end

          team_a_ids.each do |uid|
            user = by_id[uid]
            next unless user

            opponent = (mode == "singles") ? by_id[team_b_ids.first] : nil
            stats = build_stats(actor:, team_a_ids:, team_b_ids:, uid:, mode:, is_team_a: true)

            PlayerStatistics::UpsertMatchForGameService.new(
              user:, game:, actor:, mode:,
              outcome: outcome_for_a, played_at:, opponent:, score:, stats:, force_new:
            ).call
          end

          team_b_ids.each do |uid|
            user = by_id[uid]
            next unless user

            opponent = (mode == "singles") ? by_id[team_a_ids.first] : nil
            stats = build_stats(actor:, team_a_ids:, team_b_ids:, uid:, mode:, is_team_a: false)

            PlayerStatistics::UpsertMatchForGameService.new(
              user:, game:, actor:, mode:,
              outcome: outcome_for_b, played_at:, opponent:, score:, stats:, force_new:
            ).call
          end
        end

        def build_stats(actor:, team_a_ids:, team_b_ids:, uid:, mode:, is_team_a:)
          my_team = is_team_a ? team_a_ids : team_b_ids
          opp_team = is_team_a ? team_b_ids : team_a_ids

          {
            "entered_by" => actor.id,
            "team_a_ids" => team_a_ids,
            "team_b_ids" => team_b_ids,
            "partner_id" => (mode == "doubles" ? (my_team - [ uid ]).first : nil),
            "opponent_ids" => (mode == "doubles" ? opp_team : [ opp_team.first ].compact)
          }.compact
        end
      end
    end
  end
end
