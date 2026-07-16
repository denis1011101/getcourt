module PlayerStatistics
  # Applies an edited stats-form block to the existing Match rows of one logical
  # match (identified by stats["match_group_id"]): updates kept players, creates
  # rows for added players, removes rows of players taken off the teams, and
  # keeps the incremental PlayerStatistic counters consistent.
  class SyncMatchGroupService
    def initialize(game:, actor:, group_id:, mode:, team_a_ids:, team_b_ids:, result:, played_at:, score:, team_a_guest_names: [], team_b_guest_names: [])
      @game = game
      @actor = actor
      @group_id = group_id
      @mode = mode.to_s
      @team_a_ids = group_ids(team_a_ids)
      @team_b_ids = group_ids(team_b_ids)
      @result = result
      @played_at = played_at
      @score = score
      @team_a_guest_names = Array(team_a_guest_names)
      @team_b_guest_names = Array(team_b_guest_names)
    end

    # Returns true when the group was found and synced, false otherwise.
    def call
      Match.transaction do
        existing = MatchGroups.find(@game, @group_id)
        return false if existing.empty?

        existing_by_user = existing.group_by(&:user_id)
        desired_ids = @team_a_ids + @team_b_ids
        removed = existing.reject { |match| desired_ids.include?(match.user_id) }
        removed = (removed + existing_by_user.values.flat_map { |matches| matches.drop(1) }).uniq

        users_by_id = User.where(id: desired_ids).index_by(&:id)
        touched_modes = existing.map(&:mode).uniq

        removed.each { |match| remove_match!(match) }

        desired_ids.each do |uid|
          user = users_by_id[uid]
          next unless user

          row = existing_by_user[uid]&.first
          row = nil if removed.include?(row)
          if row && row.mode != @mode
            remove_match!(row)
            row = nil
          end

          UpsertMatchForGameService.new(
            user: user, game: @game, actor: @actor, mode: @mode,
            outcome: outcome_for(uid), played_at: @played_at, opponent: opponent_for(uid),
            score: @score, stats: stats_for(uid), match: row, force_new: row.nil?
          ).call
        end

        (touched_modes + [ @mode ]).uniq.each { |mode| PlayerStatistic.recalculate_elo_for_mode!(mode) }
        true
      end
    end

    private

    def group_ids(ids)
      Array(ids).map(&:to_i).uniq.reject(&:zero?)
    end

    def outcome_for(uid)
      return "draw" if @result == :draw

      winner_ids = @result == :a ? @team_a_ids : @team_b_ids
      winner_ids.include?(uid) ? "win" : "loss"
    end

    def opponent_for(uid)
      return nil unless @mode == "singles"

      opponent_id = @team_a_ids.include?(uid) ? @team_b_ids.first : @team_a_ids.first
      opponent_id ? User.find_by(id: opponent_id) : nil
    end

    def stats_for(uid)
      is_team_a = @team_a_ids.include?(uid)
      stats = Telegram::Flows::StatsScore::MatchUpserter.build_stats(
        actor: @actor, team_a_ids: @team_a_ids, team_b_ids: @team_b_ids,
        team_a_guest_names: @team_a_guest_names, team_b_guest_names: @team_b_guest_names,
        uid: uid, mode: @mode, is_team_a: is_team_a
      )
      stats["match_group_id"] = @group_id
      # build_stats compacts empty values, but on edit they must overwrite the
      # stale composition kept by the stats merge in UpsertMatchForGameService.
      stats["partner_id"] = nil unless stats.key?("partner_id")
      stats["team_a_guest_names"] = @team_a_guest_names unless stats.key?("team_a_guest_names")
      stats["team_b_guest_names"] = @team_b_guest_names unless stats.key?("team_b_guest_names")
      stats
    end

    # Mirrors the new_record branch of UpsertMatchForGameService#apply_counters_delta!
    # in reverse, then destroys the row.
    def remove_match!(match)
      user = match.user
      mode = match.mode.to_s
      ps = user.player_statistic || user.create_player_statistic

      games_key = mode == "doubles" ? :doubles_games : :singles_games
      hours_key = mode == "doubles" ? :doubles_hours : :singles_hours
      wins_key = mode == "doubles" ? :doubles_wins : :singles_wins
      losses_key = mode == "doubles" ? :doubles_losses : :singles_losses
      training_key =
        if @game.respond_to?(:with_coach?) && @game.with_coach?
          mode == "doubles" ? :group_training : :individual_training
        end

      ps.with_lock do
        if training_key
          # Mirror the creation-side activity_counted check: when a stats entry
          # already covered this visit, the match never incremented training.
          ps[training_key] = [ ps[training_key].to_i - 1, 0 ].max unless activity_counted_elsewhere?(user)
        else
          ps[games_key] = [ ps[games_key].to_i - 1, 0 ].max
        end

        if match.outcome == "win"
          ps[wins_key] = [ ps[wins_key].to_i - 1, 0 ].max
        elsif match.outcome == "loss"
          ps[losses_key] = [ ps[losses_key].to_i - 1, 0 ].max
        end

        hours = match.stats.to_h["hours"].to_f
        ps[hours_key] = [ (ps[hours_key] || 0).to_f - hours, 0.0 ].max if hours != 0.0

        ps.save!
      end

      match.destroy!
    end

    def activity_counted_elsewhere?(user)
      cycle_start = @game.respond_to?(:current_cycle_start) ? @game.current_cycle_start : nil
      scope = PlayerStatisticEntry.where(user: user, game: @game)
      scope = scope.where("recorded_at >= ?", cycle_start) if cycle_start.present?
      scope.exists?
    end
  end
end
