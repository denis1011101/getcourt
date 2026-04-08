module PlayerStatistics
  class UpsertMatchForGameService
    def initialize(user:, game:, actor:, mode:, won: nil, outcome: nil, played_at: nil, opponent: nil, score: nil, stats: {})
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
      @stats = stats || {}
    end

    def call
      played_at = @played_at || default_played_at

      Match.transaction do
        match = find_or_init_match(played_at)
        new_record = match.new_record?
        old_outcome = match.persisted? ? match.outcome.to_s : nil

        match.opponent = @opponent
        match.outcome = @outcome
        match.score = @score.to_s.presence
        match.played_at = played_at
        match.stats = (match.stats || {}).to_h.merge(@stats.to_h)
        match.save!

        apply_counters_delta!(new_record: new_record, old_outcome: old_outcome, new_outcome: @outcome)
        PlayerStatistic.recalculate_elo_for_mode!(@mode)

        match
      end
    end

    private

    def find_or_init_match(played_at)
      played_date = played_at.to_date
      existing = Match.lock
                      .where(user: @user, game: @game, mode: @mode)
                      .where(played_at: played_date.beginning_of_day..played_date.end_of_day)
                      .first

      existing || Match.new(user: @user, game: @game, mode: @mode)
    end

    def default_played_at
      start = @game.respond_to?(:start_at_for_ui) ? @game.start_at_for_ui : nil
      start || Time.current
    rescue
      Time.current
    end

    def apply_counters_delta!(new_record:, old_outcome:, new_outcome:)
      ps = @user.player_statistic || @user.create_player_statistic

      games_key = @mode == "doubles" ? :doubles_games : :singles_games
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
        ps[wins_key] = [ ps[wins_key].to_i, 0 ].max
        ps[losses_key] = [ ps[losses_key].to_i, 0 ].max

        ps.save!
      end
    end
  end
end
