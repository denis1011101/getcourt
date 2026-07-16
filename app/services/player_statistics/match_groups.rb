module PlayerStatistics
  # Groups a game's Match rows (one per registered participant) back into the
  # logical matches the stats form works with, scoped to the game's current cycle.
  module MatchGroups
    module_function

    def for_game(game)
      scope = Match.where(game_id: game.id).order(:id)
      cycle_start = game.respond_to?(:current_cycle_start) ? game.current_cycle_start : nil
      scope = scope.where("played_at >= ?", cycle_start) if cycle_start.present?

      scope.to_a.group_by { |match| group_key(match) }.values.map { |matches| build_group(matches) }
    end

    def find(game, group_id)
      return [] if group_id.blank?

      for_game(game).find { |group| group[:group_id] == group_id }&.fetch(:matches) || []
    end

    def group_key(match)
      stats = match.stats.to_h
      stats["match_group_id"] || [
        "legacy",
        match.score.to_s,
        normalize_ids(stats["team_a_ids"]),
        normalize_ids(stats["team_b_ids"]),
        normalize_names(stats["team_a_guest_names"]),
        normalize_names(stats["team_b_guest_names"])
      ].join("|")
    end

    def build_group(matches)
      match = matches.first
      stats = match.stats.to_h

      {
        group_id: stats["match_group_id"],
        score: match.score.to_s,
        winner: winner_team(match, stats),
        team_a_ids: normalize_ids(stats["team_a_ids"]),
        team_b_ids: normalize_ids(stats["team_b_ids"]),
        team_a_guest_names: normalize_names(stats["team_a_guest_names"]),
        team_b_guest_names: normalize_names(stats["team_b_guest_names"]),
        matches: matches
      }
    end

    def winner_team(match, stats)
      return "draw" if match.outcome == "draw"

      in_team_a = normalize_ids(stats["team_a_ids"]).include?(match.user_id)
      (match.outcome == "win") == in_team_a ? "a" : "b"
    end

    def normalize_ids(value)
      Array(value).map(&:to_i).uniq.sort
    end

    def normalize_names(value)
      Array(value).map(&:to_s).map(&:strip).reject(&:blank?)
    end
  end
end
