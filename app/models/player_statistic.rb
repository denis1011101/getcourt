class PlayerStatistic < ApplicationRecord
  belongs_to :user

  validates :singles_hours, :doubles_hours, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :singles_sessions, :doubles_sessions, :singles_games, :doubles_games,
            :singles_wins, :singles_losses, :doubles_wins, :doubles_losses,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  # convenience readers
  def total_hours
    (singles_hours.to_f + doubles_hours.to_f).round(2)
  end

  def singles_win_rate
    denom = (singles_wins.to_i + singles_losses.to_i)
    denom.zero? ? nil : (singles_wins.to_f / denom * 100).round(1)
  end

  def doubles_win_rate
    denom = (doubles_wins.to_i + doubles_losses.to_i)
    denom.zero? ? nil : (doubles_wins.to_f / denom * 100).round(1)
  end

  # simple ELO-ish rating update (example)
  def update_elo!(mode:, opponent_rating:, result:)
    # mode: :singles or :doubles, result: 1.0 win, 0.5 draw, 0.0 loss
    k = 32.0
    own = (mode == :singles ? (singles_rating || 1500.0) : (doubles_rating || 1500.0))
    expected = 1.0 / (1.0 + 10**((opponent_rating.to_f - own)/400.0))
    new_rating = (own + k * (result - expected)).round(1)
    if mode == :singles
      update_column(:singles_rating, new_rating)
    else
      update_column(:doubles_rating, new_rating)
    end
    new_rating
  end

  # example helper to increment counters after a match/training
  def record_match!(mode:, won:, aces: 0, double_faults: 0, first_serve_pct: nil)
    if mode == :singles
      increment!(:singles_games)
      won ? increment!(:singles_wins) : increment!(:singles_losses)
    else
      increment!(:doubles_games)
      won ? increment!(:doubles_wins) : increment!(:doubles_losses)
    end
    increment!(:aces, aces.to_i) if aces.to_i > 0
    increment!(:double_faults, double_faults.to_i) if double_faults.to_i > 0
    update_column(:first_serve_percent, first_serve_pct.to_f) if first_serve_pct
  end
end
