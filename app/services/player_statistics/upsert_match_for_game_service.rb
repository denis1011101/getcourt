module PlayerStatistics
  class UpsertMatchForGameService
    def initialize(user:, game:, actor:, mode:, won:, played_at: nil, opponent: nil, score: nil, stats: {})
      @user = user
      @game = game
      @actor = actor
      @mode = mode.to_s
      @won = !!won
      @played_at = played_at
      @opponent = opponent
      @score = score
      @stats = stats || {}
    end

    def call
      played_at = @played_at || default_played_at
      outcome = @won ? "win" : "loss"

      Match.transaction do
        match = Match.lock.find_or_initialize_by(user: @user, game: @game, mode: @mode)
        new_record = match.new_record?
        old_outcome = match.persisted? ? match.outcome.to_s : nil

        match.opponent = @opponent
        match.outcome = outcome
        match.score = @score.to_s.presence
        match.played_at = played_at
        match.stats = (match.stats || {}).to_h.merge(@stats.to_h)
        match.save!

        apply_counters_delta!(new_record: new_record, old_outcome: old_outcome, new_outcome: outcome)

        match
      end
    end

    private

    def default_played_at
      # best-effort: use game start time in creator TZ; fallback to now
      start = @game.respond_to?(:start_at_for_ui) ? @game.start_at_for_ui : nil
      start || Time.current
    rescue
      Time.current
    end

    def apply_counters_delta!(new_record:, old_outcome:, new_outcome:)
      ps = @user.player_statistic || @user.create_player_statistic

      games_key = @mode == "doubles" ? :doubles_games : :singles_games
      sessions_key = @mode == "doubles" ? :doubles_sessions : :singles_sessions
      wins_key = @mode == "doubles" ? :doubles_wins : :singles_wins
      losses_key = @mode == "doubles" ? :doubles_losses : :singles_losses

      ps.with_lock do
        if new_record
          ps[games_key] = ps[games_key].to_i + 1
          ps[sessions_key] = ps[sessions_key].to_i + 1

          if new_outcome == "win"
            ps[wins_key] = ps[wins_key].to_i + 1
          else
            ps[losses_key] = ps[losses_key].to_i + 1
          end
        else
          if old_outcome.present? && old_outcome != new_outcome
            if old_outcome == "win"
              ps[wins_key] = ps[wins_key].to_i - 1
              ps[losses_key] = ps[losses_key].to_i + 1
            elsif old_outcome == "loss"
              ps[losses_key] = ps[losses_key].to_i - 1
              ps[wins_key] = ps[wins_key].to_i + 1
            end
          end
        end

        # safety: avoid negative counters
        ps[games_key] = [ ps[games_key].to_i, 0 ].max
        ps[sessions_key] = [ ps[sessions_key].to_i, 0 ].max
        ps[wins_key] = [ ps[wins_key].to_i, 0 ].max
        ps[losses_key] = [ ps[losses_key].to_i, 0 ].max

        ps.save!
      end
    end
  end
end
