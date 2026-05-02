class UsersController < ApplicationController
  include LocationFilters

  CITY_SEARCH_DEFAULT_LIMIT = 5

  before_action :authenticate_user!

  def edit
    @user = current_user
    prepare_edit_form_state
  end

  def update
    @user = current_user

    user_attrs = user_update_params.to_h
    court_preferences_mode = params.dig(:user, :court_preferences_mode).presence || default_court_preferences_mode(@user)
    favorite_court_ids = Array(params.dig(:user, :favorite_court_ids)).reject(&:blank?)

    query = user_attrs["city_name"].to_s.strip
    if query.present?
      coords_regex = /\A\s*-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?\s*\z/
      # for plain names: transliterate immediately so DB shows e.g. "Kurgan"
      unless query =~ coords_regex
        user_attrs["city_name"] = translit_str(query)
      end
    end

    case court_preferences_mode
    when "note"
      user_attrs["court_preferences_note"] = user_attrs["court_preferences_note"].to_s.strip.presence
      user_attrs["favorite_court_ids"] = []
    else
      user_attrs["court_preferences_note"] = nil
      user_attrs["favorite_court_ids"] = favorite_court_ids
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
      @court_preferences_mode = court_preferences_mode
      prepare_edit_form_state
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

  def destroy
    current_user.destroy!
    reset_session
    redirect_to root_path, notice: t("users.account_deleted")
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
      :court_preferences_note,
      :notify_nearby,
      favorite_court_ids: [],
      preferred_sports: [],
      skill_levels: {} # permit JSON object
    )
  end

  def prepare_edit_form_state
    @registration_token = @user.ensure_telegram_registration_token!
    @limit = params[:limit].to_i.nonzero? || CITY_SEARCH_DEFAULT_LIMIT
    @available_courts = sorted_available_courts_for(@user)
    @court_preferences_mode ||= default_court_preferences_mode(@user)
    prepare_player_statistics_state

    if params[:selected_city_name].present?
      @selected_city_name = params[:selected_city_name]
    else
      c = City.find_by(timezone: @user.timezone)
      @selected_city_name = "#{c.name}, #{c.country_code} — #{c.timezone}" if c.present?
    end
  end

  def sorted_available_courts_for(user)
    courts = Court.visible_to(user).to_a
    user_city = normalized_city(user&.city_name)
    return courts.sort_by { |c| c.city_name.to_s } unless user_city

    local, other = courts.partition { |c| normalized_city(c.city_name) == user_city }
    local.sort_by { |c| c.name.to_s } + other.sort_by { |c| [ c.city_name.to_s, c.name.to_s ] }
  end

  def prepare_player_statistics_state
    @player_statistic = @user.player_statistic || @user.create_player_statistic
    @recent_matches = Match.where(user: @user).includes(:opponent, :game).order(played_at: :desc).limit(5).to_a
    related_ids = @recent_matches.flat_map do |match|
      stats = match.stats.to_h
      [ match.opponent_id, stats["partner_id"], *Array(stats["opponent_ids"]) ]
    end.compact.uniq
    @names_by_id = User.where(id: related_ids).map { |user| [ user.id, Telegram::Helpers::UserLookup.display_name(user, fallback: "User ##{user.id}") ] }.to_h
  end

  def default_court_preferences_mode(user)
    user.court_preferences_note.present? ? "note" : "favorites"
  end
end
