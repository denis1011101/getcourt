class PrebookingCancellationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_game
  before_action :set_cancellation, only: [ :destroy ]

  def create
    return head :forbidden unless current_user.admin? || @game.user == current_user
    date = parse_date(params[:date])
    return redirect_back(fallback_location: game_path(@game), alert: "Invalid date") unless date

    c = @game.prebooking_cancellations.find_or_initialize_by(date: date)
    c.user = current_user
    c.cancelled_at ||= Time.current

    if c.save
      redirect_back fallback_location: game_path(@game), notice: "Date cancelled."
    else
      redirect_back fallback_location: game_path(@game), alert: c.errors.full_messages.join(", ")
    end
  end

  def destroy
    return head :forbidden unless current_user.admin? || @game.user == current_user
    @cancellation.destroy
    redirect_back fallback_location: game_path(@game), notice: "Date restored."
  end

  private

  def set_game
    @game = Game.find(params[:game_id])
  end

  def set_cancellation
    @cancellation = @game.prebooking_cancellations.find(params[:id])
  end

  def parse_date(val)
    Date.parse(val.to_s) rescue nil
  end
end
