class PlayerStatistic < ApplicationRecord
  BASE_ELO = 1500.0
  RESET_TO_ZERO_COLUMNS = %i[
    singles_sessions doubles_sessions singles_games doubles_games
    singles_wins singles_losses doubles_wins doubles_losses
    individual_training group_training singles_hours doubles_hours
    aces double_faults break_points_saved break_points_converted
    winners unforced_errors net_points_won service_points_won
    return_points_won return_games_won games_won_total
  ].freeze
  RESET_TO_NIL_COLUMNS = %i[
    singles_rating doubles_rating first_serve_percent
  ].freeze
  ELO_RESULTS = {
    "win" => 1.0,
    "draw" => 0.5,
    "loss" => 0.0
  }.freeze

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

  # Summary stats for a user (used in rating & AI tools)
  def self.summary_for(user)
    ps = find_by(user_id: user.id)
    total_games = ps ? ps.singles_games.to_i + ps.doubles_games.to_i : 0
    total_wins  = ps ? ps.singles_wins.to_i  + ps.doubles_wins.to_i  : 0
    pct = total_games > 0 ? (total_wins.to_f / total_games * 100).round(1) : nil
    { games: total_games, wins: total_wins, win_pct: pct }
  end

  def self.reset_attributes
    RESET_TO_ZERO_COLUMNS.index_with(0).merge(RESET_TO_NIL_COLUMNS.index_with(nil))
  end

  def resettable_statistics?
    RESET_TO_ZERO_COLUMNS.any? { |column| public_send(column).to_f.nonzero? } ||
      RESET_TO_NIL_COLUMNS.any? { |column| public_send(column).present? }
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
    mode.to_sym == :singles ? (singles_rating || BASE_ELO) : (doubles_rating || BASE_ELO)
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

      self.class.recalculate_elo_for_mode!(mode)
    end
  end

  def self.recalculate_elo_for_mode!(mode)
    mode = mode.to_s
    rating_column = mode == "doubles" ? :doubles_rating : :singles_rating
    matches = Match.where(mode: mode).order(:played_at, :id).to_a
    ratings = Hash.new(BASE_ELO)
    reset_times = stats_reset_times_for_matches(matches)
    reset_applied = {}
    elo_rated_user_ids = {}

    grouped_matches(matches).each_value do |event_matches|
      apply_pending_rating_resets(event_matches, ratings, reset_times, reset_applied)
      apply_elo_for_event(event_matches, ratings, elo_rated_user_ids)
    end

    last_elo_played_at_by_user = last_elo_played_at_by_user(grouped_matches(matches).values)

    Match.where(mode: mode).distinct.pluck(:user_id).each do |user_id|
      next unless elo_rated_user_ids[user_id]

      ps = find_or_create_by!(user_id: user_id)
      rating = reset_without_later_match?(user_id, reset_times, last_elo_played_at_by_user) ? nil : ratings[user_id]
      ps.update!(rating_column => rating)
    end
  end

  def self.last_elo_played_at_by_user(grouped_event_matches)
    grouped_event_matches.each_with_object({}) do |event_matches, memo|
      event = build_elo_event(event_matches)
      next unless event

      played_at = event_matches.first.played_at
      (event[:team_a_ids] + event[:team_b_ids]).each do |user_id|
        memo[user_id] = [ memo[user_id], played_at ].compact.max
      end
    end
  end
  private_class_method :last_elo_played_at_by_user

  def self.stats_reset_times_for_matches(matches)
    user_ids = matches.flat_map { |match| elo_user_ids(match) }.compact.uniq
    where(user_id: user_ids).where.not(stats_reset_at: nil).pluck(:user_id, :stats_reset_at).to_h
  end
  private_class_method :stats_reset_times_for_matches

  def self.elo_user_ids(match)
    stats = match.stats.to_h

    if match.mode == "doubles"
      [ match.user_id, *Array(stats["team_a_ids"]), *Array(stats["team_b_ids"]) ].map(&:to_i)
    else
      [ match.user_id, match.opponent_id, *Array(stats["opponent_ids"]) ].compact.map(&:to_i)
    end
  end
  private_class_method :elo_user_ids

  def self.apply_pending_rating_resets(event_matches, ratings, reset_times, reset_applied)
    event = build_elo_event(event_matches)
    return unless event

    played_at = event_matches.first.played_at
    (event[:team_a_ids] + event[:team_b_ids]).uniq.each do |user_id|
      reset_at = reset_times[user_id]
      next unless reset_at && reset_at <= played_at && !reset_applied[user_id]

      ratings[user_id] = BASE_ELO
      reset_applied[user_id] = true
    end
  end
  private_class_method :apply_pending_rating_resets

  def self.reset_without_later_match?(user_id, reset_times, last_played_at_by_user)
    reset_at = reset_times[user_id]
    reset_at && last_played_at_by_user[user_id] && last_played_at_by_user[user_id] < reset_at
  end
  private_class_method :reset_without_later_match?

  def self.grouped_matches(matches)
    matches.group_by { |match| elo_event_key(match) }
          .sort_by { |(_, grouped)| [ grouped.first.played_at || Time.at(0), grouped.map(&:id).min ] }
          .to_h
  end
  private_class_method :grouped_matches

  def self.elo_event_key(match)
    stats = match.stats.to_h

    if match.mode == "doubles"
      team_a_ids = Array(stats["team_a_ids"]).map(&:to_i).sort
      team_b_ids = Array(stats["team_b_ids"]).map(&:to_i).sort

      [ match.mode, match.game_id, match.played_at, [ team_a_ids, team_b_ids ].sort ]
    else
      opponent_id = match.opponent_id || Array(stats["opponent_ids"]).map(&:to_i).first

      [ match.mode, match.game_id, match.played_at, [ match.user_id, opponent_id ].compact.sort ]
    end
  end
  private_class_method :elo_event_key

  def self.apply_elo_for_event(event_matches, ratings, elo_rated_user_ids)
    event = build_elo_event(event_matches)
    return unless event

    team_a_ids = event[:team_a_ids]
    team_b_ids = event[:team_b_ids]
    (team_a_ids + team_b_ids).each { |user_id| elo_rated_user_ids[user_id] = true }
    result_a = ELO_RESULTS.fetch(event[:team_a_outcome], 0.5)
    result_b = ELO_RESULTS.fetch(inverse_outcome(event[:team_a_outcome]), 0.5)

    team_a_rating = average_team_rating(team_a_ids, ratings)
    team_b_rating = average_team_rating(team_b_ids, ratings)

    updated_ratings = {}

    team_a_ids.each do |user_id|
      updated_ratings[user_id] = Ratings::EloRatingService.new(
        current_rating: ratings[user_id],
        opponent_rating: team_b_rating,
        result: result_a
      ).call
    end

    team_b_ids.each do |user_id|
      updated_ratings[user_id] = Ratings::EloRatingService.new(
        current_rating: ratings[user_id],
        opponent_rating: team_a_rating,
        result: result_b
      ).call
    end

    ratings.merge!(updated_ratings)
  end
  private_class_method :apply_elo_for_event

  def self.build_elo_event(event_matches)
    sample = event_matches.first
    stats = sample.stats.to_h
    return if guest_names_present?(stats)

    if sample.mode == "doubles"
      team_a_ids = Array(stats["team_a_ids"]).map(&:to_i).uniq
      team_b_ids = Array(stats["team_b_ids"]).map(&:to_i).uniq
      return if team_a_ids.empty? || team_b_ids.empty?

      team_a_outcome = event_matches.find { |match| team_a_ids.include?(match.user_id) }&.outcome.to_s.presence || "draw"
      { team_a_ids:, team_b_ids:, team_a_outcome: }
    else
      opponent_id = sample.opponent_id || Array(stats["opponent_ids"]).map(&:to_i).first
      opponent_id ||= (event_matches.map(&:user_id).uniq - [ sample.user_id ]).first
      return unless opponent_id

      {
        team_a_ids: [ sample.user_id ],
        team_b_ids: [ opponent_id ],
        team_a_outcome: sample.outcome.to_s.presence || "draw"
      }
    end
  end
  private_class_method :build_elo_event

  def self.guest_names_present?(stats)
    Array(stats["team_a_guest_names"]).any? || Array(stats["team_b_guest_names"]).any?
  end
  private_class_method :guest_names_present?

  def self.average_team_rating(user_ids, ratings)
    return BASE_ELO if user_ids.empty?

    user_ids.sum { |user_id| ratings[user_id] } / user_ids.size.to_f
  end
  private_class_method :average_team_rating

  def self.inverse_outcome(outcome)
    case outcome.to_s
    when "win" then "loss"
    when "loss" then "win"
    else "draw"
    end
  end
  private_class_method :inverse_outcome
end
