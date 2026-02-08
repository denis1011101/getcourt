class GamesController < ApplicationController
  before_action :handle_mark_not_happened, only: [ :show ]
  before_action :set_game, only: %i[show edit update destroy]
  before_action :authorize_manage_game!, only: %i[edit update destroy]
  skip_before_action :authenticate_user!, only: %i[index show]

  helper_method :display_date, :display_time, :game_badges

  def index
    @games = Game.includes(:court, :tournament).order(:date, :time)
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
      @game.ensure_prebookings_for_next_weeks if @game.prebooking_enabled?
      redirect_to @game, notice: "Game was successfully created."
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
      @game.ensure_prebookings_for_next_weeks if @game.prebooking_enabled?
      redirect_to @game, notice: "Game was successfully updated."
    else
      Rails.logger.warn "Game update failed: #{ @game.errors.full_messages.join('; ') }"
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @game.destroy
    redirect_to games_url, notice: "Game was successfully destroyed."
  end

  # GET /games/prebooking_fragment
  def prebooking_fragment
    if params[:game_id].present?
      @game = Game.find_by(id: params[:game_id]) || Game.new
      @game.recurring = ActiveModel::Type::Boolean.new.cast(params[:recurring])
    else
      @game = Game.new(recurring: ActiveModel::Type::Boolean.new.cast(params[:recurring]))
    end

    render partial: "games/prebooking_fragment", locals: { game: @game }
  end

  # TODO: implement marking an occurrence as "not happened".
  # For now we only log and do nothing — the button will open the game page.
  def handle_mark_not_happened
    return unless params[:mark_not_happened].present?
    Rails.logger.info("[TODO] mark_not_happened clicked for game=#{params[:id]} (not implemented)")
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
    params.require(:game).permit(:court_id, :recurring, :occurrences_per_week, :with_coach, :date, :time, :players_count, :skill_level, :sport, :prebooking_enabled)
  end

  def display_date(game)
    nd = game.display_date_for_show
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

    # sport badge (if game.sport present)
    if game.respond_to?(:sport) && game.sport.present?
      badges << { text: game.sport.to_s.titleize,
                  classes: "inline-flex items-center rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-800 mr-2" }
    end

    # required skill level (support several possible attribute names)
    skill_attr = %w[min_skill skill_level level].find { |a| game.respond_to?(a) && game.public_send(a).present? }
    if skill_attr
      lvl = game.public_send(skill_attr).to_s
      if User::SKILL_LEVELS.include?(lvl)
        badges << { text: lvl.titleize,
                    classes: "inline-flex items-center rounded-full bg-yellow-50 px-2 py-0.5 text-xs font-medium text-yellow-700 mr-2" }
      end
    end

    # with_coach / need coach
    if game.respond_to?(:with_coach) && game.with_coach?
      badges << { text: "With coach",
                  classes: "inline-flex items-center rounded-full bg-blue-50 px-2 py-0.5 text-xs font-medium text-blue-700 mr-2" }
    elsif game.respond_to?(:needs_coach) && game.needs_coach?
      badges << { text: "Need coach",
                  classes: "inline-flex items-center rounded-full bg-blue-50/20 px-2 py-0.5 text-xs font-medium text-blue-700 mr-2" }
    end

    if game.respond_to?(:participations)
      required = (game.respond_to?(:players_count) && game.players_count.to_i > 0) ? game.players_count.to_i : 4
      approved_participations = game.participations.respond_to?(:approved) ? game.participations.approved : game.participations
      taken = approved_participations.size
      spots_left = required - taken
      badges << {
        text: "#{spots_left} spot#{'s' if spots_left != 1} left — #{taken}/#{required}",
        classes: "inline-flex items-center rounded-full bg-red-50 px-2 py-0.5 text-xs font-medium text-red-700 mr-2"
      }
    end

    # recurring / weekly
    if game.respond_to?(:recurring) && game.recurring?
      badges << { text: "Weekly",
                  classes: "inline-flex items-center rounded-full bg-green-50 px-2 py-0.5 text-xs font-medium text-green-700 mr-2" }
    end

    badges
  end

  def sanitized_game_params
    gp = game_params.to_h
    gp["date"] = gp["date"].presence
    gp["time"] = gp["time"].presence
    gp["recurring"] = ActiveModel::Type::Boolean.new.cast(gp["recurring"]) if gp.key?("recurring")
    gp["with_coach"] = ActiveModel::Type::Boolean.new.cast(gp["with_coach"]) if gp.key?("with_coach")
    gp["occurrences_per_week"] = gp["occurrences_per_week"].to_i if gp.key?("occurrences_per_week")
    gp["players_count"] = gp["players_count"].to_i if gp.key?("players_count")
    gp["sport"] = gp["sport"].presence if gp.key?("sport")
    gp["skill_level"] = gp["skill_level"].presence if gp.key?("skill_level")
    gp
  end
end
