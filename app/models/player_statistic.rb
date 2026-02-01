class PlayerStatistic < ApplicationRecord
  belongs_to :user

  validates :singles_sessions, :doubles_sessions, :singles_games, :doubles_games,
            :singles_wins, :singles_losses, :doubles_wins, :doubles_losses,
            :individual_training, :group_training,
            :aces, :double_faults, :break_points_saved, :break_points_converted,
            :winners, :unforced_errors, :net_points_won, :service_points_won,
            :return_points_won, :return_games_won, :games_won_total,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  # Generic helper: :int / :float based on schema type
  def self.numeric_field_type(field)
    t = type_for_attribute(field.to_s).type
    return :int if t == :integer
    :float
  rescue
    :int
  end

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

  def rating(mode)
    mode.to_sym == :singles ? (singles_rating || 1500.0) : (doubles_rating || 1500.0)
  end

  # ELO update via service (без update_column)
  def update_elo!(mode:, opponent_rating:, result:, k_factor: Ratings::EloRatingService::DEFAULT_K)
    new_rating = Ratings::EloRatingService.new(
      current_rating: rating(mode),
      opponent_rating: opponent_rating,
      result: result,
      k_factor: k_factor
    ).call

    if mode.to_sym == :singles
      update!(singles_rating: new_rating)
    else
      update!(doubles_rating: new_rating)
    end

    new_rating
  end

  # record a match + increment counters safely
  def record_match!(mode:, won:, aces: 0, double_faults: 0, first_serve_pct: nil, played_at: Time.current, opponent: nil, surface: nil, score: nil, game: nil)
    PlayerStatistic.transaction do
      Match.create!(
        user: user,
        opponent: opponent,
        game: game,
        mode: mode.to_s,
        outcome: (won ? "win" : "loss"),
        surface: surface,
        score: score,
        played_at: played_at,
        stats: {
          "aces" => aces.to_i,
          "double_faults" => double_faults.to_i,
          "first_serve_percent" => (first_serve_pct.nil? ? nil : first_serve_pct.to_f)
        }.compact
      )

      with_lock do
        attrs = {}

        if mode.to_sym == :singles
          attrs[:singles_games] = singles_games.to_i + 1
          if won
            attrs[:singles_wins] = singles_wins.to_i + 1
          else
            attrs[:singles_losses] = singles_losses.to_i + 1
          end
        else
          attrs[:doubles_games] = doubles_games.to_i + 1
          if won
            attrs[:doubles_wins] = doubles_wins.to_i + 1
          else
            attrs[:doubles_losses] = doubles_losses.to_i + 1
          end
        end

        attrs[:aces] = self.aces.to_i + aces.to_i if aces.to_i > 0
        attrs[:double_faults] = self.double_faults.to_i + double_faults.to_i if double_faults.to_i > 0
        attrs[:first_serve_percent] = first_serve_pct.to_f if first_serve_pct.present?

        update!(attrs)
      end
    end
  end
end
