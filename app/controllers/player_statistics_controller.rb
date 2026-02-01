class PlayerStatisticsController < ApplicationController
  before_action :set_user, except: :create_for_game

  def show
    @stats = @user.player_statistic || @user.create_player_statistic
    matches = Match.where(user: @user).includes(:opponent, :game).order(played_at: :desc).limit(5).to_a
    related_ids = matches.flat_map do |m|
      s = (m.stats || {}).to_h
      [ m.opponent_id, s["partner_id"], *Array(s["opponent_ids"]) ]
    end.compact.uniq

    names_by_id =
      if related_ids.any?
        User.where(id: related_ids).map { |u| [ u.id, (u.name.to_s.strip.presence || u.telegram_username.to_s.strip.presence || u.email.to_s) ] }.to_h
      else
        {}
      end

    render partial: "player_statistics/modal", locals: { user: @user, stats: @stats, matches: matches, names_by_id: names_by_id }
  end

  def create_for_game
    game = Game.find(params[:game_id])

    allowed = allowed_to_fill_stats?(game)
    started = game_started?(game)

    if allowed && started
      raw = player_statistics_params.to_h
      data = {}
      score = raw.delete("score")

      hours = raw.delete("hours")
      if hours.present?
        field = StatisticsPresenter.hours_field_for_game(game)
        data[field.to_s] = hours
      end

      raw.each do |key, value|
        if value.present? && StatisticsPresenter.allowed_keys.include?(key.to_s)
          data[key.to_s] = value
        end
      end

      saved_any = false

      if data.present?
        PlayerStatistics::ApplyEntryToParticipantsService.new(
          game: game,
          actor: current_user,
          data: data,
          source: "web",
          recorded_at: Time.current,
          include_creator: true
        ).call

        increment_activity_for_game!(game)
        saved_any = true
      end

      if score.present?
        team_params = team_ids_params
        team_a_ids = sanitize_team_ids(team_params[:team_a_user_ids], game)
        team_b_ids = sanitize_team_ids(team_params[:team_b_user_ids], game)
        winner = params[:winner_team].to_s

        if team_a_ids.any? && team_b_ids.any? && %w[a b].include?(winner)
          upsert_matches_for_teams(game, team_a_ids, team_b_ids, score, winner)
          increment_activity_for_game!(game)
          saved_any = true
        end
      end

      if saved_any
        redirect_to game_path(game), notice: "Statistics saved."
      else
        redirect_to game_path(game), alert: "No data to save."
      end
    else
      if allowed == false
        redirect_to game_path(game), alert: "Not allowed."
      else
        redirect_to game_path(game), alert: "Statistics can be entered after the game starts."
      end
    end
  end

private

def player_statistics_params
  params.require(:statistics).permit(
    :score,
    :hours,
    :singles_games,
    :doubles_games,
    :aces,
    :double_faults,
    :break_points_saved,
    :break_points_converted,
    :winners,
    :unforced_errors,
    :net_points_won,
    :service_points_won,
    :return_points_won,
    :return_games_won,
    :games_won_total
  )
end

def team_ids_params
  params.permit(team_a_user_ids: [], team_b_user_ids: [])
end

  def set_user
    @user = User.find(params[:user_id] || params[:id])
  end

  def allowed_to_fill_stats?(game)
    current_user && (current_user == game.user || (current_user.respond_to?(:admin?) && current_user.admin?))
  end

  def game_started?(game)
    if game.respond_to?(:starts_at) && game.starts_at.present?
      game.starts_at <= Time.current
    elsif game.respond_to?(:date) && game.date.present?
      game.date <= Date.current
    else
      true
    end
  end

  def game_participants(game)
    users = []
    users << game.user if game.respond_to?(:user)
    if game.respond_to?(:participations)
      users.concat(game.participations.includes(:user).map(&:user))
    end
    users.compact.uniq { |u| u.id }
  end

  def sanitize_team_ids(ids, game)
    allowed_ids = game_participants(game).map(&:id)
    Array(ids).map(&:to_i).uniq.select { |id| allowed_ids.include?(id) }
  end

  def upsert_matches_for_teams(game, team_a_ids, team_b_ids, score, winner)
    played_at =
      if game.respond_to?(:starts_at) && game.starts_at.present?
        game.starts_at
      elsif game.respond_to?(:date) && game.date.present?
        game.date.to_time
      else
        Time.current
      end

    mode = if team_a_ids.size >= 2 || team_b_ids.size >= 2
             "doubles"
           else
             "singles"
           end

    team_a_ids.each do |user_id|
      outcome = winner == "a" ? "win" : "loss"
      opponent_id = mode == "singles" && team_b_ids.size == 1 ? team_b_ids.first : nil
      upsert_match(game, user_id, opponent_id, mode, outcome, score, played_at)
    end

    team_b_ids.each do |user_id|
      outcome = winner == "b" ? "win" : "loss"
      opponent_id = mode == "singles" && team_a_ids.size == 1 ? team_a_ids.first : nil
      upsert_match(game, user_id, opponent_id, mode, outcome, score, played_at)
    end
  end

  def upsert_match(game, user_id, opponent_id, mode, outcome, score, played_at)
    match = Match.find_or_initialize_by(user_id: user_id, game_id: game.id)
    match.opponent_id = opponent_id
    match.mode = mode
    match.outcome = outcome
    match.score = score
    match.played_at = played_at
    match.save!
  end

  def increment_activity_for_game!(game)
    already_counted =
      PlayerStatisticEntry.where(game: game).exists? ||
      Match.where(game_id: game.id).exists?

    if already_counted
      return
    end

    users = game_participants(game)

    mode = StatisticsPresenter.hours_field_for_game(game) == :doubles_hours ? :doubles : :singles

    training_key = nil
    if game.respond_to?(:with_coach?) && game.with_coach?
      if mode == :doubles
        training_key = :group_training
      else
        training_key = :individual_training
      end
    end

    users.each do |u|
      ps = u.player_statistic || u.create_player_statistic
      ps.with_lock do
        if training_key
          ps[training_key] = ps[training_key].to_i + 1
          ps[training_key] = [ps[training_key].to_i, 0].max
        else
          games_key = mode == :doubles ? :doubles_games : :singles_games
          ps[games_key] = ps[games_key].to_i + 1
          ps[games_key] = [ps[games_key].to_i, 0].max
        end
        ps.save!
      end
    end
  end
end
