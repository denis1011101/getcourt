class PrebookingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_game
  before_action :set_prebooking, only: %i[book cancel]

  def book
    return head :forbidden unless can_participate?(@game, @prebooking.date)

    if @prebooking.user_id.present?
      redirect_back fallback_location: game_path(@game), alert: "Slot already taken."
      return
    end

    if @game.prebookings.where(user_id: current_user.id, date: @prebooking.date).exists?
      redirect_back fallback_location: game_path(@game), alert: "You already have a booking for this game on that date."
      return
    end

    @prebooking.update!(user: current_user)
    redirect_back fallback_location: game_path(@game), notice: "You booked a slot."
  end

  def cancel
    if @prebooking.user == current_user || respond_to?(:can_manage?) && can_manage?(@game)
      @prebooking.update!(user: nil)
      redirect_back fallback_location: game_path(@game), notice: "Booking cleared."
    else
      head :forbidden
    end
  end

  private

  def set_game
    @game = Game.find(params[:game_id])
  end

  def set_prebooking
    @prebooking = @game.prebookings.find(params[:id])
  end

  def can_participate?(game, date = nil)
    return false unless game&.prebooking_enabled?

    scope = game.prebookings
    scope = scope.where(date: date) if date.present?
    taken = scope.where.not(user_id: nil).count
    capacity = (game.players_count.to_i > 0 ? game.players_count.to_i : 4)
    taken < capacity
  end
end
