class PrebookingsController < ApplicationController
  before_action :authenticate_user!, except: :more
  before_action :set_game
  before_action :set_prebooking, only: %i[book cancel approve reject]

  def more
    @horizon = params[:horizon].to_i.clamp(3, Game::MAX_PREBOOKING_HORIZON)
    dates = @game.prebooking_candidate_dates(@horizon)
    @game.ensure_prebookings_for_dates(@game.prebooking_horizon_dates(@horizon)) if current_user.present?
    render partial: "games/prebookings", locals: { game: @game, horizon: @horizon }
  end

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

    direct_book = current_user == @game.user || (current_user.respond_to?(:admin?) && current_user.admin?)
    status = direct_book ? "approved" : "pending"

    @prebooking.update!(user: current_user, status: status, approved_at: direct_book ? Time.current : nil)

    if status == "pending"
      schedule_owner_notification(@game, current_user)
      redirect_back fallback_location: game_path(@game), notice: "Booking request sent. Waiting for approval."
    else
      redirect_back fallback_location: game_path(@game), notice: "You booked a slot."
    end
  end

  def cancel
    if @prebooking.user == current_user || can_manage_game?
      @prebooking.update!(user: nil, status: "approved", approved_at: nil)
      redirect_back fallback_location: game_path(@game), notice: "Booking cleared."
    else
      head :forbidden
    end
  end

  def approve
    return head :forbidden unless can_manage_game?

    @prebooking.update!(status: "approved", approved_at: Time.current)
    GameRequestNotification.prebooking(user: @prebooking.user, game: @game, dates: @prebooking.date, approved: true)
    redirect_back fallback_location: game_path(@game), notice: "Prebooking approved."
  end

  def reject
    return head :forbidden unless can_manage_game?

    requester = @prebooking.user
    date = @prebooking.date
    @prebooking.update!(user: nil, status: "approved", approved_at: nil)
    GameRequestNotification.prebooking(user: requester, game: @game, dates: date, approved: false)
    redirect_back fallback_location: game_path(@game), notice: "Prebooking rejected."
  end

  private

  def set_game
    @game = Game.find(params[:game_id])
  end

  def set_prebooking
    @prebooking = @game.prebookings.find(params[:id])
  end

  def can_manage_game?
    current_user && (current_user == @game.user || (current_user.respond_to?(:admin?) && current_user.admin?))
  end

  def can_participate?(game, date = nil)
    return false unless game&.prebooking_enabled?

    # запрещаем, если дата отменена
    if date.present? && PrebookingCancellation.exists?(game_id: game.id, date: date)
      return false
    end

    scope = game.prebookings
    scope = scope.where(date: date) if date.present?
    taken = scope.where.not(user_id: nil).count
    capacity = (game.players_count.to_i > 0 ? game.players_count.to_i : 4)
    taken < capacity
  end

  def schedule_owner_notification(game, user)
    batch_ts = Time.current.to_f.to_s
    cache_key = "prebooking_notify:#{game.id}:#{user.id}"
    Rails.cache.write(cache_key, batch_ts, expires_in: 25.seconds)
    NotifyPrebookingOwnerJob.set(wait: 20.seconds).perform_later(game.id, user.id, batch_ts)
  end
end
