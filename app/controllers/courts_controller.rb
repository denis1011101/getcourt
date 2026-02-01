class CourtsController < ApplicationController
  before_action :set_court, only: %i[show edit update destroy approve reject]
  skip_before_action :authenticate_user!, only: %i[index show]

  def index
    @courts = Court.visible_to(current_user)
    Rails.logger.info "Courts#index current_user_id=#{current_user&.id} courts=#{@courts.map { |c| [c.id, c.user_id] }.inspect}"
  end

  def show
    unless current_user&.admin? || @court.approved?
      redirect_to courts_path, alert: "This court is under moderation." and return
    end
  end

  def new
    @court = Court.new
  end

  def create
    @court = Court.new(court_params)
    @court.user = current_user if current_user.present?
    @court.moderation_status = "pending"
    @court.approved_at = nil
    Rails.logger.info "Courts#create before_save user_id=#{@court.user_id} current_user_id=#{current_user&.id}"

    if @court.save
      Rails.logger.info "Courts#create saved court_id=#{@court.id} user_id=#{@court.user_id}"
      Telegram::AdminNotifier.notify_court_pending(@court, base_url: request.base_url, action: "created")
      redirect_to courts_path, notice: "Your court is under moderation. We will publish it after approval."
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @court.update(court_params.merge(moderation_status: "pending", approved_at: nil))
      Telegram::AdminNotifier.notify_court_pending(@court, base_url: request.base_url, action: "updated")
      redirect_to courts_path, notice: "Your changes are under moderation. We will publish them after approval."
    else
      render :edit
    end
  end

  def approve
    return head :forbidden unless current_user&.admin?

    @court.update(moderation_status: "approved", approved_at: Time.current)
    redirect_to @court, notice: "Court approved."
  end

  def reject
    return head :forbidden unless current_user&.admin?

    @court.update(moderation_status: "rejected", approved_at: nil)
    redirect_to courts_path, notice: "Court rejected."
  end

  def destroy
    unless can_manage?(@court) || (@court.user_id == current_user&.id)
      head :forbidden and return
    end

    @court.destroy
    redirect_to courts_path, notice: 'Court was successfully destroyed.'
  end

  private

  def set_court
    @court = Court.find(params[:id])
  end

  def court_params
    params.require(:court).permit(:name, :coordinates, :user_id, :contact_type, :contact_value)
  end
end
