class TournamentsController < ApplicationController
  # redirect to login when non-authenticated users call mutating actions
  before_action :authenticate_user!, only: %i[new create edit update destroy join leave select_bracket reset_bracket add_match]
  before_action :set_tournament, only: %i[options show edit update destroy join leave select_bracket reset_bracket add_match]
  before_action :authorize_organizer!, only: %i[edit update destroy select_bracket reset_bracket add_match]

  def index
    scope = Tournament.includes(:tournament_participants, :courts, :games).order(created_at: :desc)

    if params[:my_tournaments].present? && current_user
      scope = scope.where(
        "tournaments.user_id = :uid OR tournaments.id IN (SELECT tournament_id FROM tournament_participants WHERE user_id = :uid)",
        uid: current_user.id
      )
    end

    scope = scope.where(format: params[:tournament_format]) if Tournament::FORMATS.include?(params[:tournament_format])
    scope = scope.where(tournament_type: params[:tournament_type]) if Tournament.tournament_types.key?(params[:tournament_type])

    tournaments = scope.to_a

    if current_user&.city_name.present?
      user_city = current_user.city_name.downcase
      local, other = tournaments.partition { |t| t.courts.any? { |c| c.city_name.to_s.downcase == user_city } }
      tournaments = local + other
    end

    @tournaments = tournaments
  end

  def new
    @tournament = Tournament.new(tournament_type: "bracket", format: "singles")
  end

  def create
    @tournament = Tournament.new(tournament_params.merge(user: current_user))
    if @tournament.save
      redirect_to options_tournaments_path(tournament_id: @tournament.id), notice: t("tournaments.flash.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @tournament.update(tournament_params)
      redirect_to @tournament, notice: t("tournaments.flash.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @tournament.destroy
    redirect_to tournaments_path, notice: t("tournaments.flash.destroyed")
  end

  def options
    if @tournament
      cached = Rails.cache.read("tournament:#{@tournament.id}:bracket")
      @variants = cached ? [ cached ] : generate_bracket_variants(@tournament)
    else
      redirect_to tournaments_path
    end
  end

  def show
    @participants = @tournament.tournament_participants.includes(:user).order(:created_at)
    @matches = @tournament.tournament_matches.includes(:player_a, :player_b, :player_a2, :player_b2).order(:played_at, :id)
    @standings = TournamentStandings.compute(@tournament)
    @games = @tournament.games.includes(:court, :tournament, :participations, :prebooking_cancellations).order(:date, :time)
  end

  def join
    if @tournament.participant_for(current_user)
      redirect_back fallback_location: tournament_path(@tournament)
    elsif @tournament.full? && !@tournament.organizer?(current_user)
      @tournament.tournament_participants.create!(user: current_user, name: participant_name_for(current_user), status: "pending")
      redirect_back fallback_location: tournament_path(@tournament), notice: t("tournaments.flash.join_requested")
    else
      @tournament.tournament_participants.create!(user: current_user, name: participant_name_for(current_user), status: "approved", approved_at: Time.current)
      redirect_back fallback_location: tournament_path(@tournament), notice: t("tournaments.flash.joined")
    end
  end

  def leave
    @tournament.participant_for(current_user)&.destroy
    redirect_back fallback_location: tournament_path(@tournament), notice: t("tournaments.flash.left")
  end

  def select_bracket
    # prevent creating games twice
    if @tournament.games.exists?
      redirect_back fallback_location: tournament_path(@tournament), alert: t("tournaments.flash.bracket_exists")
      return
    end

    unless @tournament.default_court
      redirect_back fallback_location: tournament_path(@tournament), alert: t("tournaments.flash.no_court")
      return
    end

    variants = generate_bracket_variants(@tournament)
    chosen = variants[params[:variant].to_i] || variants.first
    # Create first-round games from the chosen variant, spread over the days the tournament runs.
    # A player drawn against a BYE advances without playing, so that pair gets no game.
    played_pairs = chosen[:rounds].first.map { |pair| pair.reject { |player| player == "BYE" } }.select { |players| players.size > 1 }
    dates = @tournament.schedule_dates_for(played_pairs.size)

    played_pairs.each_with_index do |players, index|
      player_ids = players.filter_map { |entry| @tournament.tournament_participants.find_by(name: entry)&.user_id }
      @tournament.create_game!(organizer: current_user, player_ids: player_ids, date: dates[index])
    end

    redirect_to tournament_path(@tournament), notice: t("tournaments.flash.bracket_created")
  end

  def add_match
    unless @tournament.started?
      redirect_back fallback_location: tournament_path(@tournament), alert: t("tournaments.flash.not_started")
      return
    end

    player_a = resolve_participant(:player_a_id)
    player_b = resolve_participant(:player_b_id)
    doubles = @tournament.doubles?
    player_a2 = doubles ? resolve_participant(:player_a2_id) : nil
    player_b2 = doubles ? resolve_participant(:player_b2_id) : nil

    unless player_a && player_b
      redirect_back fallback_location: tournament_path(@tournament), alert: t("tournaments.flash.select_both_players")
      return
    end

    if doubles && (!player_a2 || !player_b2)
      redirect_back fallback_location: tournament_path(@tournament), alert: t("tournaments.flash.select_four_players")
      return
    end

    team_a_ids = [ player_a.id, player_a2&.id ].compact
    team_b_ids = [ player_b.id, player_b2&.id ].compact
    all_player_ids = (team_a_ids + team_b_ids).compact
    if all_player_ids.uniq.size != all_player_ids.size
      redirect_back fallback_location: tournament_path(@tournament), alert: t("tournaments.flash.players_must_differ")
      return
    end

    score = params[:score].to_s.strip
    if score.blank?
      redirect_back fallback_location: tournament_path(@tournament), alert: t("tournaments.flash.score_required")
      return
    end

    parsed = TournamentStandings.parse_score(score)
    unless parsed
      redirect_back fallback_location: tournament_path(@tournament), alert: t("tournaments.flash.score_invalid")
      return
    end

    # Prevent duplicate pair in round_robin (symmetric check)
    if @tournament.round_robin? && pair_already_played?(team_a_ids, team_b_ids, doubles: doubles)
      redirect_back fallback_location: tournament_path(@tournament), alert: t("tournaments.flash.pair_already_played")
      return
    end

    result = if parsed[:sets_a] > parsed[:sets_b]
      "player_a"
    elsif parsed[:sets_b] > parsed[:sets_a]
      "player_b"
    else
      parsed[:games_a] > parsed[:games_b] ? "player_a" : (parsed[:games_b] > parsed[:games_a] ? "player_b" : "draw")
    end

    unless @tournament.default_court
      redirect_back fallback_location: tournament_path(@tournament), alert: t("tournaments.flash.no_court")
      return
    end

    played_at = Time.current
    TournamentMatch.create!(
      tournament: @tournament,
      player_a: player_a,
      player_b: player_b,
      player_a2: player_a2,
      player_b2: player_b2,
      score: score,
      result: result,
      played_at: played_at
    )

    game = @tournament.create_game!(organizer: current_user, player_ids: all_player_ids, date: @tournament.date_for_played_match)

    Telegram::Flows::StatsScore::MatchUpserter.call(
      game: game,
      actor: current_user,
      mode: doubles ? "doubles" : "singles",
      team_a_ids: team_a_ids,
      team_b_ids: team_b_ids,
      result: result == "player_a" ? :a : (result == "player_b" ? :b : :draw),
      played_at: played_at,
      score: score
    )

    redirect_to tournament_path(@tournament), notice: t("tournaments.flash.match_added")
  rescue ActiveRecord::RecordNotUnique
    redirect_back fallback_location: tournament_path(@tournament), alert: t("tournaments.flash.match_exists")
  end

  # destroy games created for bracket (reset)
  def reset_bracket
    @tournament.games.destroy_all
    Rails.cache.delete("tournament:#{@tournament.id}:bracket")
    Rails.cache.delete("tournament:#{@tournament.id}:selected_variant")
    redirect_back fallback_location: tournament_path(@tournament), notice: t("tournaments.flash.bracket_reset")
  end

  private
    # ensure only tournament owner/organizer can perform destructive actions
    def authorize_organizer!
      unless @tournament&.organizer?(current_user)
        redirect_back fallback_location: tournaments_path, alert: t("tournaments.flash.not_authorized")
      end
    end

    # Прошедшие турниры сносит CleanupPastTournamentsJob, а ссылки на них
    # остаются в поиске и в чужих постах. Без этой строки show падал с 500 на
    # каждой такой ссылке — сейчас в проде турниров нет вовсе, и пятисотили
    # все адреса подряд. Правильный ответ на удалённое — 404.
    def set_tournament
      @tournament = Tournament.find_by(id: params[:tournament_id] || params[:id])
      raise ActiveRecord::RecordNotFound if @tournament.nil? && action_name != "options"
    end

    def participant_name_for(user)
      user.name.presence || user.email
    end

    def resolve_participant(param_key)
      user_id = params[param_key].to_i
      return nil if user_id <= 0

      participant = @tournament.tournament_participants.find_by(user_id: user_id)
      participant&.user
    end

    def pair_already_played?(team_a_ids, team_b_ids, doubles:)
      if doubles
        team_a_sorted = team_a_ids.sort
        team_b_sorted = team_b_ids.sort

        @tournament.tournament_matches.any? do |tm|
          played_a = [ tm.player_a_id, tm.player_a2_id ].compact.sort
          played_b = [ tm.player_b_id, tm.player_b2_id ].compact.sort

          (played_a == team_a_sorted && played_b == team_b_sorted) ||
            (played_a == team_b_sorted && played_b == team_a_sorted)
        end
      else
        @tournament.tournament_matches.where(
          "(player_a_id = :a AND player_b_id = :b) OR (player_a_id = :b AND player_b_id = :a)",
          a: team_a_ids.first, b: team_b_ids.first
        ).exists?
      end
    end

    def tournament_params
      params.require(:tournament).permit(:name, :players_count, :games_count, :format, :tournament_type, :start_date, :end_date, :time, court_ids: [], dates: [])
    end

    # Simple fallback bracket generator — returns an array of variants.
    # Replace with a dedicated service later.
    def generate_bracket_variants(t)
      n = (t&.players_count || 0).to_i
      return [] if n < 2

      # smallest power of two >= n
      size = 1
      size *= 2 while size < n
      byes = size - n

      # use real participants when tournament persisted
      participants = if t.persisted?
        t.approved_participants.includes(:user).map { |p| p.display_name.presence || "Player #{p.id}" }
      else
        (1..n).map { |i| "Player #{i}" }
      end

      # First-round pairings: every BYE goes to a different player (who then advances
      # without playing), so two BYEs never end up in the same pair.
      players = participants.shuffle
      pairings = Array.new(byes) { [ players.shift, "BYE" ] }
      pairings.concat(players.each_slice(2).to_a)

      [
        {
          name: "Standard bracket (#{size} slots)",
          size: size,
          byes: byes,
          rounds: [ pairings ]
        }
      ]
    end
end
