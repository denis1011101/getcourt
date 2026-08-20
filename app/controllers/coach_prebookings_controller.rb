class CoachPrebookingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_game
  before_action :authorize_coach!

  def create
    booking = @game.coach_prebookings.create!(coach: current_user, date: params[:date])
    redirect_back fallback_location: game_path(@game), notice: t("games.prebookings.coach_booked")
  rescue ActiveRecord::RecordInvalid => error
    redirect_back fallback_location: game_path(@game), alert: error.record.errors.full_messages.to_sentence
  end

  def destroy
    # Тренеров у тренировки двое, и чужой id брони приходит тем же маршрутом —
    # поэтому отменить можно только собственное подтверждение.
    @game.coach_prebookings.where(coach: current_user).find(params[:id]).destroy!
    redirect_back fallback_location: game_path(@game), notice: t("games.prebookings.coach_cancelled")
  end

  private

  def set_game
    @game = Game.find(params[:game_id])
  end

  def authorize_coach!
    head :forbidden unless @game.accepted_coach?(current_user)
  end
end
