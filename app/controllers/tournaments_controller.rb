class TournamentsController < ApplicationController
  # redirect to login when non-authenticated users call mutating actions
  before_action :authenticate_user!, only: %i[new create join leave select_bracket reset_bracket add_match]
  before_action :set_tournament, only: %i[options show join leave select_bracket reset_bracket add_match]
  before_action :authorize_organizer!, only: %i[select_bracket reset_bracket add_match]

  def index
    @tournaments = Tournament.includes(:tournament_participants).order(created_at: :desc)

    if params[:my_tournaments].present? && current_user
      @tournaments = @tournaments.where(
        "tournaments.user_id = :uid OR tournaments.id IN (SELECT tournament_id FROM tournament_participants WHERE user_id = :uid)",
        uid: current_user.id
      )
    end
  end

  def new
    @tournament = Tournament.new
  end

  def create
    @tournament = Tournament.new(tournament_params.merge(user: current_user))
    if @tournament.save
      redirect_to options_tournaments_path(tournament_id: @tournament.id)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def options
    @tournament ||= Tournament.new(tournament_params_from_params)
    cached = @tournament.persisted? && Rails.cache.read("tournament:#{@tournament.id}:bracket")
    @variants = cached ? [ cached ] : generate_bracket_variants(@tournament)
  end

  def show
  end

  def join
    @tournament = Tournament.find(params[:id])
    @tournament.tournament_participants.find_or_create_by!(user: current_user) do |p|
      p.name = current_user.try(:name) || current_user.email
    end
    redirect_back fallback_location: tournament_path(@tournament)
  end

  def leave
    @tournament = Tournament.find(params[:id])
    tp = @tournament.tournament_participants.find_by(user: current_user)
    tp&.destroy
    redirect_back fallback_location: tournament_path(@tournament)
  end

  def select_bracket
    @tournament = Tournament.find(params[:id])

    # prevent creating games twice
    if @tournament.games.exists?
      redirect_back fallback_location: tournament_path(@tournament), alert: "Bracket already created. Reset first to recreate."
      return
    end

    variants = generate_bracket_variants(@tournament)
    chosen = variants[params[:variant].to_i] || variants.first
    # create first-round games from chosen variant (simple implementation)
    chosen[:rounds].first.each do |pair|
      players = pair.reject { |p| p == "BYE" }
      next if players.empty?

      # choose a court for the game (use tournament's first court or fallback to any court)
      court = @tournament.courts.first || Court.first
      g = Game.create!(tournament: @tournament, court: court, user: current_user, date: Date.today)

      players.each do |entry|
        tp = @tournament.tournament_participants.find_by(name: entry)
        Participation.create!(game: g, user: tp.user) if tp&.user
      end
    end

    redirect_to tournament_path(@tournament)
  end

  def add_match
    unless @tournament.started?
      redirect_back fallback_location: tournament_path(@tournament), alert: "Statistics available after tournament starts."
      return
    end

    player_a = resolve_participant(:player_a_id)
    player_b = resolve_participant(:player_b_id)

    unless player_a && player_b
      redirect_back fallback_location: tournament_path(@tournament), alert: "Select both players."
      return
    end

    if player_a.id == player_b.id
      redirect_back fallback_location: tournament_path(@tournament), alert: "Players must be different."
      return
    end

    score = params[:score].to_s.strip
    if score.blank?
      redirect_back fallback_location: tournament_path(@tournament), alert: "Enter score (e.g. 6-4 6-3)."
      return
    end

    parsed = TournamentStandings.parse_score(score)
    unless parsed
      redirect_back fallback_location: tournament_path(@tournament), alert: "Invalid score format. Use e.g. 6-4 6-3."
      return
    end

    # Prevent duplicate pair in round_robin (symmetric check)
    if @tournament.round_robin?
      exists = TournamentMatch.where(tournament_id: @tournament.id)
                              .where(
                                "(player_a_id = :a AND player_b_id = :b) OR (player_a_id = :b AND player_b_id = :a)",
                                a: player_a.id, b: player_b.id
                              ).exists?
      if exists
        redirect_back fallback_location: tournament_path(@tournament), alert: "This pair already played in this tournament."
        return
      end
    end

    result = if parsed[:sets_a] > parsed[:sets_b]
      "player_a"
    elsif parsed[:sets_b] > parsed[:sets_a]
      "player_b"
    else
      parsed[:games_a] > parsed[:games_b] ? "player_a" : (parsed[:games_b] > parsed[:games_a] ? "player_b" : "draw")
    end

    TournamentMatch.create!(
      tournament: @tournament,
      player_a: player_a,
      player_b: player_b,
      score: score,
      result: result,
      played_at: Time.current
    )

    redirect_to tournament_path(@tournament), notice: "Match added."
  rescue ActiveRecord::RecordNotUnique
    redirect_back fallback_location: tournament_path(@tournament), alert: "This match already exists."
  end

  # destroy games created for bracket (reset)
  def reset_bracket
    @tournament = Tournament.find(params[:id])
    @tournament.games.destroy_all
    Rails.cache.delete("tournament:#{@tournament.id}:bracket")
    Rails.cache.delete("tournament:#{@tournament.id}:selected_variant")
    redirect_back fallback_location: tournament_path(@tournament), notice: "Bracket reset."
  end

  private

  # ensure only tournament owner/organizer can perform destructive actions
  def authorize_organizer!
    set_tournament unless @tournament
    unless current_user && @tournament && @tournament.user_id == current_user.id
      redirect_back fallback_location: tournaments_path, alert: "You are not authorized to perform this action."
    end
  end

  def set_tournament
    @tournament = Tournament.find_by(id: params[:tournament_id] || params[:id])
  end

  def resolve_participant(param_key)
    user_id = params[param_key].to_i
    return nil if user_id <= 0

    participant = @tournament.tournament_participants.find_by(user_id: user_id)
    participant&.user
  end

  def tournament_params
    params.require(:tournament).permit(:name, :players_count, :games_count, :format, :start_date, :end_date, :time, court_ids: [], dates: [])
  end

  def tournament_params_from_params
    return {} unless params[:tournament].present?
    params.require(:tournament).permit(:name, :players_count, :games_count, :format, :start_date, :end_date, :time, court_ids: [], dates: [])
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
      t.tournament_participants.includes(:user).map { |p| p.name.presence || p.user&.name || "Player #{p.id}" }
    else
      (1..n).map { |i| "Player #{i}" }
    end

    players = participants.dup
    players += Array.new(byes) { "BYE" }
    players.shuffle! # перемешиваем участников и BYE

    # first-round pairings
    pairings = players.each_slice(2).to_a

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
