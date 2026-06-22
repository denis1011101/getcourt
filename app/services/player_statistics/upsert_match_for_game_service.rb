module PlayerStatistics
  class UpsertMatchForGameService
    def initialize(user:, game:, actor:, mode:, won: nil, outcome: nil, played_at: nil, opponent: nil, score: nil, hours: nil, stats: {}, force_new: false)
      @user = user
      @game = game
      @actor = actor
      @mode = mode.to_s

      # backward-compatible:
      # - old callers pass won: true/false
      # - new callers can pass outcome: "win"/"loss"/"draw"
      @outcome =
        outcome.to_s.presence ||
          (won.nil? ? "draw" : (won ? "win" : "loss"))

      @played_at = played_at
      @opponent = opponent
      @score = score
      @hours = hours
      @stats = stats || {}
      @force_new = force_new
    end

    def call
      played_at = @played_at || default_played_at

      Match.transaction do
        match = find_or_init_match(played_at)
        new_record = match.new_record?
        old_outcome = match.persisted? ? match.outcome.to_s : nil
        old_hours = match.stats.to_h["hours"]

        match.opponent = @opponent
        match.outcome = @outcome
        match.score = @score.to_s.presence
        match.played_at = played_at
        match.stats = (match.stats || {}).to_h.merge(@stats.to_h).tap do |stats|
          stats["hours"] = @hours if @hours.present?
        end
        match.save!

        apply_counters_delta!(
          new_record: new_record,
          old_outcome: old_outcome,
          new_outcome: @outcome,
          old_hours: old_hours,
          new_hours: match.stats.to_h["hours"]
        )
        PlayerStatistic.recalculate_elo_for_mode!(@mode)

        match
      end
    end

    private

    def find_or_init_match(played_at)
      played_date = played_at.to_date
      return find_or_init_manual_match(played_date) if @game.nil?
      return Match.new(user: @user, game: @game, mode: @mode) if @force_new

      existing = Match.lock
                      .where(user: @user, game: @game, mode: @mode)
                      .where(played_at: played_date.beginning_of_day..played_date.end_of_day)
                      .first

      existing || Match.new(user: @user, game: @game, mode: @mode)
    end

    def find_or_init_manual_match(played_date)
      scope = Match.lock
                   .where(user: @user, game: nil, mode: @mode)
                   .where(played_at: played_date.beginning_of_day..played_date.end_of_day)

      existing =
        if @mode == "doubles"
          team_a_ids = normalize_ids(@stats["team_a_ids"])
          team_b_ids = normalize_ids(@stats["team_b_ids"])

          scope.to_a.find do |match|
            stats = match.stats.to_h
            normalize_ids(stats["team_a_ids"]) == team_a_ids &&
              normalize_ids(stats["team_b_ids"]) == team_b_ids
          end
        else
          opponent_id = @opponent&.id || normalize_ids(@stats["opponent_ids"]).first

          scope.to_a.find do |match|
            match.opponent_id == opponent_id ||
              normalize_ids(match.stats.to_h["opponent_ids"]).first == opponent_id
          end
        end

      existing || Match.new(user: @user, game: nil, mode: @mode)
    end

    def default_played_at
      start = @game.respond_to?(:start_at_for_ui) ? @game.start_at_for_ui : nil
      start || Time.current
    rescue
      Time.current
    end

    def normalize_ids(value)
      Array(value).map(&:to_i).uniq.sort
    end

    def apply_counters_delta!(new_record:, old_outcome:, new_outcome:, old_hours:, new_hours:)
      ps = @user.player_statistic || @user.create_player_statistic

      games_key = @mode == "doubles" ? :doubles_games : :singles_games
      hours_key = @mode == "doubles" ? :doubles_hours : :singles_hours
      wins_key = @mode == "doubles" ? :doubles_wins : :singles_wins
      losses_key = @mode == "doubles" ? :doubles_losses : :singles_losses

      training_key = nil
      if @game.respond_to?(:with_coach?) && @game.with_coach?
        if @mode == "doubles"
          training_key = :group_training
        else
          training_key = :individual_training
        end
      end

      # Skip activity increment only for coach sessions where stats entry already
      # counted the training visit for this user+game in the current cycle.
      activity_counted = if new_record && training_key.present?
        cycle_start = @game.respond_to?(:current_cycle_start) ? @game.current_cycle_start : nil
        scope = PlayerStatisticEntry.where(user: @user, game: @game)
        scope = scope.where("recorded_at >= ?", cycle_start) if cycle_start.present?
        scope.exists?
      else
        false
      end

      ps.with_lock do
        if new_record
          unless activity_counted
            if training_key
              ps[training_key] = ps[training_key].to_i + 1
            else
              ps[games_key] = ps[games_key].to_i + 1
            end
          end

          if new_outcome == "win"
            ps[wins_key] = ps[wins_key].to_i + 1
          elsif new_outcome == "loss"
            ps[losses_key] = ps[losses_key].to_i + 1
          end
        else
          if old_outcome.present? && old_outcome != new_outcome
            if old_outcome == "win"
              ps[wins_key] = ps[wins_key].to_i - 1
            elsif old_outcome == "loss"
              ps[losses_key] = ps[losses_key].to_i - 1
            end

            if new_outcome == "win"
              ps[wins_key] = ps[wins_key].to_i + 1
            elsif new_outcome == "loss"
              ps[losses_key] = ps[losses_key].to_i + 1
            end
          end
        end

        ps[games_key] = [ ps[games_key].to_i, 0 ].max
        if training_key
          ps[training_key] = [ ps[training_key].to_i, 0 ].max
        end
        hours_delta = new_hours.to_f - old_hours.to_f
        ps[hours_key] = [ (ps[hours_key] || 0).to_f + hours_delta, 0.0 ].max if hours_delta != 0.0
        ps[wins_key] = [ ps[wins_key].to_i, 0 ].max
        ps[losses_key] = [ ps[losses_key].to_i, 0 ].max

        ps.save!
      end
    end
  end
end
