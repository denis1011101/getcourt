class UsersController < ApplicationController
  include LocationFilters

  CITY_SEARCH_DEFAULT_LIMIT = 5

  before_action :authenticate_user!

  def edit
    @user = current_user
    prepare_player_statistics_state
  end

  def profile
    @user = current_user
    prepare_profile_form_state
  end

  def notifications
    @user = current_user
    prepare_notifications_form_state
  end

  def security
    @user = current_user
  end

  def courts
    @user = current_user
    prepare_court_preferences_state
  end

  def update
    @user = current_user

    user_attrs = user_update_params.to_h
    section = update_section
    user_params = params[:user] || {}
    court_preferences_submitted = user_params.key?(:court_preferences_mode) || user_params.key?(:favorite_court_ids)
    court_preferences_mode = user_params[:court_preferences_mode].presence || default_court_preferences_mode(@user)

    query = user_attrs["city_name"].to_s.strip
    if query.present?
      coords_regex = /\A\s*-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?\s*\z/
      # for plain names: transliterate immediately so DB shows e.g. "Kurgan"
      unless query =~ coords_regex
        user_attrs["city_name"] = translit_str(query)
      end
    end

    if court_preferences_submitted
      favorite_court_ids = Array(user_params[:favorite_court_ids]).reject(&:blank?)

      case court_preferences_mode
      when "note"
        user_attrs["court_preferences_note"] = user_attrs["court_preferences_note"].to_s.strip.presence
        user_attrs["favorite_court_ids"] = []
      else
        user_attrs["court_preferences_note"] = nil
        user_attrs["favorite_court_ids"] = favorite_court_ids
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
        format.html { redirect_to update_section_path(section), notice: "Account updated" }
        format.json { render json: { success: true, city_name: @user.city_name, timezone: @user.timezone } }
      end
    else
      Rails.logger.info "[UsersController#update] update failed errors=#{@user.errors.full_messages.inspect}"
      @court_preferences_mode = court_preferences_mode
      prepare_section_state(section)
      respond_to do |format|
        format.html { render update_section_template(section), status: :unprocessable_entity }
        format.json { render json: { success: false, errors: @user.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def regenerate_token
    @user = current_user
    @registration_token = @user.regenerate_telegram_registration_token!
    redirect_to notifications_account_path, notice: "Token regenerated"
  end

  def clear_city
    @user = current_user
    @user.update(timezone: nil, city_name: nil)
    redirect_to profile_account_path, notice: "City cleared"
  end

  def games
    @coach_schedule =
      if current_user.coach?
        recurring_dates = current_user.coach_prebookings
          .joins(:game)
          .where(date: Date.current.., games: { coach_id: current_user.id, coach_invitation_status: "accepted" })
          .includes(game: [ :court, { participations: :user } ])
          .map { |booking| { game: booking.game, date: booking.date } }
        one_off_dates = current_user.coached_games
          .where(recurring: false, coach_invitation_status: "accepted", date: Date.current..)
          .includes(:court, participations: :user)
          .map { |game| { game: game, date: game.date } }

        (recurring_dates + one_off_dates).sort_by { |entry| [ entry[:date], entry[:game].time.to_s ] }
      else
        []
      end
    order_sql =
      if Game.column_names.include?("next_date")
        "COALESCE(games.next_date, games.date) DESC NULLS LAST, games.time DESC"
      else
        "games.date DESC NULLS LAST, games.time DESC"
      end

    @games = Game.where(
      "games.user_id = :uid OR games.id IN " \
      "(SELECT game_id FROM participations WHERE user_id = :uid AND status = 'approved')",
      uid: current_user.id
    )
    .includes(:court, participations: :user)
    .order(Arel.sql(order_sql))
    @pagy, @games = pagy(@games, items: 20)

    shown_game_ids = @games.map(&:id)

    past_matches_scope = Match
      .where(user_id: current_user.id)
      .where.not(played_at: nil)
      .order(played_at: :desc)
      .limit(200)

    if shown_game_ids.any?
      past_matches_scope = past_matches_scope.where(
        "matches.game_id IS NULL OR matches.game_id NOT IN (?)",
        shown_game_ids
      )
    end

    past_matches = past_matches_scope.to_a

    related_ids = past_matches.flat_map do |match|
      stats = match.stats.to_h
      [ match.opponent_id, stats["partner_id"], *Array(stats["opponent_ids"]), *Array(stats["team_a_ids"]), *Array(stats["team_b_ids"]) ]
    end.compact.uniq
    @opponents_by_id = User.where(id: related_ids).each_with_object({}) do |user, result|
      result[user.id] = user.name.presence || user.email
    end

    @past_match_groups = past_matches.group_by { |m| m.played_at.to_date }
                                     .sort_by { |k, _| k }
                                     .reverse
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
      :notification_channel,
      favorite_court_ids: [],
      preferred_sports: [],
      skill_levels: {} # permit JSON object
    )
  end

  def prepare_notifications_form_state
    @registration_token = @user.ensure_telegram_registration_token!
  end

  def prepare_profile_form_state
    @limit = params[:limit].to_i.nonzero? || CITY_SEARCH_DEFAULT_LIMIT

    if params[:selected_city_name].present?
      @selected_city_name = params[:selected_city_name]
    else
      c = City.find_by(timezone: @user.timezone)
      @selected_city_name = "#{c.name}, #{c.country_code} — #{c.timezone}" if c.present?
    end
  end

  def prepare_court_preferences_state
    @available_courts = sorted_available_courts_for(@user)
    @court_preferences_mode ||= default_court_preferences_mode(@user)
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
      [ match.opponent_id, stats["partner_id"], *Array(stats["opponent_ids"]), *Array(stats["team_a_ids"]), *Array(stats["team_b_ids"]) ]
    end.compact.uniq
    @names_by_id = User.where(id: related_ids).map { |user| [ user.id, Telegram::Helpers::UserLookup.display_name(user, fallback: "User ##{user.id}") ] }.to_h
  end

  def default_court_preferences_mode(user)
    user.court_preferences_note.present? ? "note" : "favorites"
  end

  def update_section
    params[:section].to_s.presence_in(%w[profile notifications security courts]) || "profile"
  end

  def update_section_path(section)
    case section
    when "notifications" then notifications_account_path
    when "security" then security_account_path
    when "courts" then courts_account_path
    else profile_account_path
    end
  end

  def update_section_template(section)
    case section
    when "notifications" then :notifications
    when "security" then :security
    when "courts" then :courts
    else :profile
    end
  end

  def prepare_section_state(section)
    case section
    when "notifications" then prepare_notifications_form_state
    when "courts" then prepare_court_preferences_state
    when "profile" then prepare_profile_form_state
    end
  end
end
