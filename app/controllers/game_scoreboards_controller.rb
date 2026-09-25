# Живое табло игры: смотреть может любой, вести счёт — те же люди, что
# заполняют статистику (организатор, одобренные участники, админ), и только
# после начала игры.
class GameScoreboardsController < ApplicationController
  skip_before_action :authenticate_user!, only: :show
  before_action :set_game
  before_action :set_scoreboard, only: %i[edit update score unscore tiebreak reset_tiebreak finish]
  before_action :require_scorer!, except: :show

  def show
    @scoreboard = @game.scoreboards.live.first
    @can_score = can_score?
    @last_finished = @game.scoreboards.where(status: "finished").order(finished_at: :desc).first unless @scoreboard
  end

  def create
    existing = @game.scoreboards.live.first
    return redirect_to(game_scoreboard_path(@game)) if existing

    @scoreboard = @game.scoreboards.new(
      user: current_user,
      settings: settings_params,
      team_a: team_from(params[:team_a]),
      team_b: team_from(params[:team_b])
    )

    if @scoreboard.save
      redirect_to game_scoreboard_path(@game)
    else
      @can_score = true
      render :show, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    # Второй телефон завёл табло одновременно с первым — подхватываем его.
    redirect_to game_scoreboard_path(@game)
  end

  def edit
  end

  def update
    if @scoreboard.update_setup!(settings: settings_params, team_a: team_from(params[:team_a]), team_b: team_from(params[:team_b]))
      redirect_to game_scoreboard_path(@game)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def score
    @scoreboard.score!(side_param, unit_param)
    respond_with_board
  end

  def unscore
    @scoreboard.unscore!(side_param, unit_param)
    respond_with_board
  end

  def tiebreak
    @tiebreak_error = @scoreboard.record_tiebreak!(params[:a], params[:b])
    respond_with_board
  end

  def reset_tiebreak
    @scoreboard.reset_tiebreak!
    respond_with_board
  end

  def finish
    @scoreboard.finish!(current_user)
    redirect_to game_path(@game), notice: t("game_scoreboards.flash.finished")
  end

  private

  def set_game
    @game = Game.find(params[:game_id])
  end

  # Табло закрыли с другого телефона — показываем, что счёт уже записан.
  def set_scoreboard
    @scoreboard = @game.scoreboards.live.first
    return if @scoreboard

    redirect_to game_scoreboard_path(@game)
  end

  def require_scorer!
    return if can_score?

    redirect_to game_scoreboard_path(@game), alert: t("game_scoreboards.flash.not_allowed")
  end

  def can_score?
    return false unless current_user
    return false if @game.training?
    return false unless @game.started_for_ui?
    return true if current_user == @game.user || current_user.admin?

    @game.participations.approved.exists?(user_id: current_user.id)
  end

  def respond_with_board
    respond_to do |format|
      format.turbo_stream do
        @scoreboard.reload
        # Табло видят все, а кнопки — только тот, кто ведёт счёт: их меняем в
        # ответе ему, не в рассылке (поле тай-брейка появляется после 7:6).
        render turbo_stream: [
          turbo_stream.replace("game_scoreboard", partial: "game_scoreboards/board", locals: { scoreboard: @scoreboard }),
          turbo_stream.replace("game_scoreboard_controls", partial: "game_scoreboards/controls",
                               locals: { scoreboard: @scoreboard, tiebreak_error: @tiebreak_error, tiebreak_input: params.permit(:a, :b).to_h })
        ]
      end
      format.html { redirect_to game_scoreboard_path(@game) }
    end
  end

  def side_param
    %w[a b].include?(params[:side]) ? params[:side] : "a"
  end

  def unit_param
    GameScoreboard::UNITS.include?(params[:unit]) ? params[:unit] : "main"
  end

  def settings_params
    raw = params.fetch(:settings, {}).permit(:mode, :sets_to_win, :tiebreak, :golden_point)
    {
      "mode" => raw[:mode].presence || "points",
      "sets_to_win" => raw[:sets_to_win].presence || 2,
      "tiebreak" => raw[:tiebreak] == "1",
      "golden_point" => raw[:golden_point] == "1"
    }
  end

  # Значения селектов: «u:<id>» — участник, «g:<имя>» — гость игры. Берём
  # только людей этой игры: чужой id из формы в статистику не попадёт.
  def team_from(values)
    allowed_ids = scorer_candidates.filter_map { |player| player.id if player.is_a?(User) }
    allowed_guests = scorer_candidates.grep(String)

    picked = Array(values).map(&:to_s).reject(&:blank?).uniq
    {
      "user_ids" => picked.filter_map { |value| value.delete_prefix("u:").to_i if value.start_with?("u:") }.select { |id| allowed_ids.include?(id) },
      "guest_names" => picked.filter_map { |value| value.delete_prefix("g:") if value.start_with?("g:") }.select { |name| allowed_guests.include?(name) }
    }
  end

  def scorer_candidates
    @scorer_candidates ||= helpers.scoreboard_candidates(@game)
  end
end
