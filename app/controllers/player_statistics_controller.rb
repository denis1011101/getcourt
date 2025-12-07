class PlayerStatisticsController < ApplicationController
  before_action :set_user

  def show
    @stats = @user.player_statistic || @user.create_player_statistic
    render partial: "player_statistics/modal", locals: { user: @user, stats: @stats }
  end

  private

  def set_user
    @user = User.find(params[:user_id] || params[:id])
  end
end
