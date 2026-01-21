class TournamentsController < ApplicationController
  # redirect to login when non-authenticated users call mutating actions
  before_action :authenticate_user!, only: %i[new create join leave select_bracket reset_bracket]
  before_action :set_tournament, only: %i[options show join leave select_bracket reset_bracket]
  before_action :authorize_organizer!, only: %i[select_bracket reset_bracket]

  def index
    @tournaments = Tournament.order(created_at: :desc)
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
    @variants = cached ? [cached] : generate_bracket_variants(@tournament)
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

  def tournament_params
    params.require(:tournament).permit(:name, :players_count, :format, :start_date, :end_date, court_ids: [], dates: [])
  end

  def tournament_params_from_params
    return {} unless params[:tournament].present?
    params.require(:tournament).permit(:name, :players_count, :format, :start_date, :end_date, court_ids: [], dates: [])
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
        rounds: [pairings]
      }
    ]
  end
end
