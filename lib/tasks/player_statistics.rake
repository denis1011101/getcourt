namespace :player_statistics do
  desc "Remove exact duplicate player-centric matches and rebuild core match statistics"
  task dedupe_matches: :environment do
    duplicate_groups = Match.order(:id).to_a.group_by do |match|
      stats = match.stats.to_h

      [
        match.user_id,
        match.game_id,
        match.mode,
        match.played_at&.to_i,
        match.opponent_id,
        match.score.to_s,
        match.outcome.to_s,
        Array(stats["team_a_ids"]).map(&:to_i).reject(&:zero?).uniq.sort,
        Array(stats["team_b_ids"]).map(&:to_i).reject(&:zero?).uniq.sort,
        stats["partner_id"].to_i.nonzero?,
        Array(stats["opponent_ids"]).map(&:to_i).reject(&:zero?).uniq.sort,
        stats["hours"].to_f,
        stats["entered_by"].to_i.nonzero?
      ]
    end.select { |_key, matches| matches.size > 1 }

    removed_count = 0

    Match.transaction do
      duplicate_groups.each_value do |matches|
        matches.drop(1).each do |match|
          match.destroy!
          removed_count += 1
        end
      end
    end

    PlayerStatistic.update_all(
      singles_hours: 0,
      doubles_hours: 0,
      singles_games: 0,
      doubles_games: 0,
      singles_wins: 0,
      singles_losses: 0,
      doubles_wins: 0,
      doubles_losses: 0,
      singles_rating: nil,
      doubles_rating: nil
    )

    Match.distinct.pluck(:user_id).each do |user_id|
      user = User.find_by(id: user_id)
      next unless user

      singles = Match.where(user_id: user.id, mode: "singles").to_a
      doubles = Match.where(user_id: user.id, mode: "doubles").to_a
      ps = user.player_statistic || user.create_player_statistic

      ps.update!(
        singles_hours: singles.sum { |match| match.stats.to_h["hours"].to_f },
        doubles_hours: doubles.sum { |match| match.stats.to_h["hours"].to_f },
        singles_games: singles.size,
        doubles_games: doubles.size,
        singles_wins: singles.count { |match| match.outcome == "win" },
        singles_losses: singles.count { |match| match.outcome == "loss" },
        doubles_wins: doubles.count { |match| match.outcome == "win" },
        doubles_losses: doubles.count { |match| match.outcome == "loss" },
        singles_rating: nil,
        doubles_rating: nil
      )
    end

    PlayerStatistic.recalculate_elo_for_mode!(:singles)
    PlayerStatistic.recalculate_elo_for_mode!(:doubles)

    puts "Removed #{removed_count} duplicate matches from #{duplicate_groups.size} duplicate groups."
  end

  desc "Fill Match#surface from the game each match was played in"
  task backfill_match_surfaces: :environment do
    filled = 0

    Match.where(surface: nil).where.not(game_id: nil).includes(game: :court).find_each do |match|
      game = match.game
      court_surfaces = Array(game&.court&.surfaces)
      surface = game&.surface.presence || (court_surfaces.first if court_surfaces.size == 1)
      next if surface.blank? || !Match::SURFACES.include?(surface)

      match.update_columns(surface: surface)
      filled += 1
    end

    puts "Matches given a surface: #{filled}"
  end
end
