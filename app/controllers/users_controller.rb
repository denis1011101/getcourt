class UsersController < ApplicationController
  CITY_SEARCH_DEFAULT_LIMIT = 5

  before_action :authenticate_user!

  def edit
    @user = current_user
    @registration_token = @user.ensure_telegram_registration_token!
    @limit = params[:limit].to_i.nonzero? || CITY_SEARCH_DEFAULT_LIMIT
    # show selected city name either from params (after click) or from saved timezone
    if params[:selected_city_name].present?
      @selected_city_name = params[:selected_city_name]
    else
      c = City.find_by(timezone: @user.timezone)
      @selected_city_name = "#{c.name}, #{c.country_code} — #{c.timezone}" if c.present?
    end
  end

  def update
    @user = current_user

    user_attrs = user_update_params.to_h

    query = user_attrs["city_name"].to_s.strip
    if query.present?
      coords_regex = /\A\s*-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?\s*\z/
      # for plain names: transliterate immediately so DB shows e.g. "Kurgan"
      unless query =~ coords_regex
        user_attrs["city_name"] = translit_str(query)
      end
    end

    Rails.logger.info "[UsersController#update] saving user_attrs=#{user_attrs.inspect}"

    if @user.update(user_attrs)
      # enqueue background job to resolve timezone asynchronously (by coords or by name)
      if query.present?
        ResolveUserCityJob.perform_later(@user.id, query)
        Rails.logger.info "[UsersController#update] enqueued ResolveUserCityJob for user_id=#{@user.id} query=#{query.inspect}"
      end

      respond_to do |format|
        format.html { redirect_to edit_account_path, notice: "Account updated" }
        format.json { render json: { success: true, city_name: @user.city_name, timezone: @user.timezone } }
      end
    else
      Rails.logger.info "[UsersController#update] update failed errors=#{@user.errors.full_messages.inspect}"
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { success: false, errors: @user.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def regenerate_token
    @user = current_user
    @registration_token = @user.regenerate_telegram_registration_token!
    redirect_to edit_account_path, notice: "Token regenerated"
  end

  def clear_city
    @user = current_user
    @user.update(timezone: nil, city_name: nil)
    redirect_to edit_account_path, notice: "City cleared"
  end

  private

  def translit_str(s)
    Russian.translit(s.to_s)
  end

  def user_update_params
    params.require(:user).permit(
      :name,
      :email,
      :telegram_username,
      :coach,
      :about_me,
      :require_verification,
      :preferred_login_via,
      :timezone,
      :city_name,
      :notify_nearby,
      preferred_sports: [],
      skill_levels: {} # permit JSON object
    )
  end
end
