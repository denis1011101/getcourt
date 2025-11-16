class CourtsController < ApplicationController
  before_action :set_court, only: %i[show edit update destroy]

  def index
    @courts = Court.all
    Rails.logger.info "Courts#index current_user_id=#{current_user&.id} courts=#{@courts.map { |c| [c.id, c.user_id] }.inspect}"
  end

  def show
  end

  def new
    @court = Court.new
  end

def create
  @court = Court.new(court_params)
  @court.user = current_user if current_user.present?
  Rails.logger.info "Courts#create before_save user_id=#{@court.user_id} current_user_id=#{current_user&.id}"

  if @court.save
    Rails.logger.info "Courts#create saved court_id=#{@court.id} user_id=#{@court.user_id}"
    redirect_to @court, notice: 'Court was successfully created.'
  else
    render :new
  end
end

  def edit
  end

  def update
    if @court.update(court_params)
      redirect_to @court, notice: 'Court was successfully updated.'
    else
      render :edit
    end
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
