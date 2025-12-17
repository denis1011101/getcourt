class UsersController < ApplicationController
  before_action :authenticate_user!

  def edit
    @user = current_user
    @registration_token = @user.ensure_telegram_registration_token!
  end

  def update
    @user = current_user
    if @user.update(user_update_params)
      redirect_to edit_account_path, notice: "Account updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def regenerate_token
    @user = current_user
    @registration_token = @user.regenerate_telegram_registration_token!
    redirect_to edit_account_path, notice: "Token regenerated"
  end

  private

  def user_update_params
    params.require(:user).permit(:name, :email, :telegram_username, :coach,
                                 :require_verification, :preferred_login_via, :timezone,
                                 preferred_sports: [],
                                 skill_levels: {}) # permit JSON object
  end
end
