class GamesController < ApplicationController
  before_action :set_game, only: %i[show edit update destroy]
  before_action :authorize_manage_game!, only: %i[edit update destroy]
  skip_before_action :authenticate_user!, only: %i[index show]

  helper_method :display_date, :display_time, :game_badges

  def index
    @games = Game.all
  end

  def show
  end

  def new
    @game = Game.new
  end

  def create
    gp = sanitized_game_params
    @game = Game.new(gp.merge(user: current_user))

    if @game.save
      redirect_to @game, notice: 'Game was successfully created.'
    else
      Rails.logger.warn "Game save failed: #{ @game.errors.full_messages.join('; ') }"
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    gp = sanitized_game_params
    if @game.update(gp)
      redirect_to @game, notice: 'Game was successfully updated.'
    else
      Rails.logger.warn "Game update failed: #{ @game.errors.full_messages.join('; ') }"
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @game.destroy
    redirect_to games_url, notice: 'Game was successfully destroyed.'
  end

  private

  def authorize_manage_game!
    unless can_manage?(@game)
      head :forbidden
    end
  end

  def set_game
    @game = Game.find(params[:id])
  end

  def game_params
    params.require(:game).permit(:court_id, :recurring, :occurrences_per_week, :with_coach, :date, :time)
  end

  def display_date(game)
    nd = game.next_date
    nd ? nd.strftime("%Y-%m-%d") : (game.date.presence || "—")
  end

  def display_time(game)
    nt = game.next_time
    if nt.is_a?(String)
      nt.presence || "—"
    elsif nt.respond_to?(:strftime)
      nt.strftime("%H:%M")
    else
      "—"
    end
  end

  def game_badges(game)
    badges = []
    badges << { text: "With coach", classes: "inline-flex items-center rounded-full bg-blue-50 px-2 py-0.5 text-xs font-medium text-blue-700 mr-2" } if game.with_coach?
    badges << { text: "Weekly",     classes: "inline-flex items-center rounded-full bg-green-50 px-2 py-0.5 text-xs font-medium text-green-700 mr-2" } if game.recurring?
    badges
  end

  def sanitized_game_params
    gp = game_params.to_h
    gp["date"] = gp["date"].presence
    gp["time"] = gp["time"].presence
    gp["recurring"] = ActiveModel::Type::Boolean.new.cast(gp["recurring"]) if gp.key?("recurring")
    gp["with_coach"] = ActiveModel::Type::Boolean.new.cast(gp["with_coach"]) if gp.key?("with_coach")
    gp["occurrences_per_week"] = gp["occurrences_per_week"].to_i if gp.key?("occurrences_per_week")
    gp
  end
end
