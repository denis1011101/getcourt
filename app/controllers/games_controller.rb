class GamesController < ApplicationController
  include LocationFilters

  before_action :handle_mark_not_happened, only: [ :show ]
  before_action :set_game, only: %i[show edit update destroy toggle_urgent_player_search accept_coach_invitation decline_coach_invitation]
  before_action :authorize_manage_game!, only: %i[edit update destroy toggle_urgent_player_search]
  before_action :prepare_coaches, only: %i[new create edit update]
  skip_before_action :authenticate_user!, only: %i[index show]

  helper_method :display_date, :display_time, :game_badges

  def index
    @featured_match = FeaturedMatch.banner.first
    @sports = SportCatalog::SPORTS
    @skill_levels = Game.where.not(skill_level: [ nil, "" ]).distinct.order(:skill_level).pluck(:skill_level)

    court_city_names = Court.where.not(city_name: [ nil, "" ]).distinct.pluck(:city_name)
    city_country_map = build_city_country_map(court_city_names)
    normalize_location_params!(city_country_map)

    canonical_path = canonical_games_path_for(city_country_map)
    if request.get? && canonical_path.present? && request.fullpath != canonical_path
      redirect_to canonical_path, status: :moved_permanently and return
    end

    prepare_location_filters(court_city_names)
    @canonical_games_url = "https://#{ApplicationHelper.canonical_host_for(request)}#{canonical_path || request.path}"
    @games_meta_title = games_meta_title_for(city_country_map)
    @games_meta_description = games_meta_description_for(city_country_map)

    if params[:country].present?
      cities_in_country = cities_for_country(params[:country])
    end

    search = Games::Search.new
      .sport(params[:sport])
      .skill_level(params[:skill_level])
      .urgent_only(params[:looking_for_players])
      .tournament_only(params[:tournament_games])

    if params[:city].present?
      search.in_cities(params[:city])
    elsif params[:country].present? && cities_in_country.to_a.any?
      search.in_cities(cities_in_country)
    end

    scoped_games = search.ordered

    if params[:my_games].present? && current_user
      scoped_games = scoped_games.where(
        "games.user_id = :uid OR games.id IN (SELECT game_id FROM participations WHERE user_id = :uid)",
        uid: current_user.id
      )
    end

    if params[:with_spots].present? || current_user&.city_name.present?
      games = scoped_games.to_a
      games = Games::Search.with_spots(games) if params[:with_spots].present?
      games = sort_games_for_user(games)
      @pagy, @games = pagy_array(games)
    else
      @pagy, @games = pagy(scoped_games)
    end
  end

  def show
  end

  def new
    @game = Game.new
  end

  def create
    gp = sanitized_game_params
    @game = Game.new(gp.merge(user: current_user))

    if @game.save
      @game.ensure_prebookings_for_next_weeks if @game.prebooking_enabled?
      @game.coaches.each { |coach| deliver_coach_invitation(coach) }
      redirect_to @game, notice: "Game was successfully created."
    else
      Rails.logger.warn "Game save failed: #{ @game.errors.full_messages.join('; ') }"
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    previous_coach_ids = @game.assigned_coach_ids
    gp = sanitized_game_params
    if @game.update(gp)
      @game.ensure_prebookings_for_next_weeks if @game.prebooking_enabled?
      invited_coaches = @game.coaches.reject { |coach| previous_coach_ids.include?(coach.id) }
      invited_coaches.each { |coach| deliver_coach_invitation(coach) }
      # The web form saves every field at once, so one message covers the whole edit.
      GameChangeNotifier.notify(game: @game, actor: current_user, changes: @game.saved_changes)
      redirect_to @game, notice: "Game was successfully updated."
    else
      Rails.logger.warn "Game update failed: #{ @game.errors.full_messages.join('; ') }"
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @game.destroy
    redirect_to games_url, notice: "Game was successfully destroyed."
  end

  def accept_coach_invitation
    return head :forbidden unless @game.answer_coach_invitation!(current_user, "accepted")

    redirect_to @game, notice: t("games.show.coach_invitation_accepted")
  end

  def decline_coach_invitation
    return head :forbidden unless @game.answer_coach_invitation!(current_user, "declined")

    redirect_to @game, notice: t("games.show.coach_invitation_declined")
  end

  def toggle_urgent_player_search
    was_enabled = @game.urgent_player_search?
    @game.update!(urgent_player_search: !was_enabled)
    if !was_enabled && @game.urgent_player_search?
      PostToThreadsJob.perform_later(@game.id, I18n.locale.to_s)
    end
    state = @game.urgent_player_search? ? "enabled" : "disabled"
    redirect_to @game, notice: "Players search #{state}."
  end

  # GET /games/prebooking_fragment
  def prebooking_fragment
    if params[:game_id].present?
      @game = Game.find_by(id: params[:game_id]) || Game.new
      @game.recurring = ActiveModel::Type::Boolean.new.cast(params[:recurring])
    else
      @game = Game.new(recurring: ActiveModel::Type::Boolean.new.cast(params[:recurring]))
    end

    render partial: "games/prebooking_fragment", locals: { game: @game }
  end

  # TODO: implement marking an occurrence as "not happened".
  # For now we only log and do nothing — the button will open the game page.
  def handle_mark_not_happened
    return unless params[:mark_not_happened].present?
    Rails.logger.info("[TODO] mark_not_happened clicked for game=#{params[:id]} (not implemented)")
  end

  private

  def prepare_coaches
    @coaches = User.not_merged.where(coach: true).order(:name)
  end

  def deliver_coach_invitation(coach)
    GameInvitationDelivery.new(
      game: @game,
      inviter: current_user,
      game_url: game_url(@game)
    ).deliver(user: coach, role: :coach)
  rescue => error
    Rails.logger.error("[GamesController] coach invitation failed: #{error.class}: #{error.message}")
  end

  def authorize_manage_game!
    unless can_manage?(@game)
      head :forbidden
    end
  end

  def set_game
    @game = Game.find(params[:id])
  end

  def sort_games_for_user(games)
    return games.sort_by { |game| time_sort_key(game) } unless current_user&.city_name.present?

    user_city = normalized_city(current_user.city_name)
    return games.sort_by { |game| time_sort_key(game) } unless user_city

    local, other = games.partition { |game| normalized_city(game.court&.city_name) == user_city }
    local_upcoming, local_past = local.partition { |game| upcoming_game?(game) }
    other_upcoming, other_past = other.partition { |game| upcoming_game?(game) }

    sorted_local_upcoming = local_upcoming.sort_by { |game| local_upcoming_sort_key(game, user_city) }
    sorted_local_past = local_past.sort_by { |game| time_sort_key(game) }
    sorted_other_upcoming = other_upcoming.sort_by { |game| time_sort_key(game) }
    sorted_other_past = other_past.sort_by { |game| time_sort_key(game) }

    sorted_local_upcoming + sorted_local_past + sorted_other_upcoming + sorted_other_past
  end

  def upcoming_game?(game)
    date = game_sorting_date(game)
    date.nil? || date >= Date.current
  end

  def time_sort_key(game)
    date = game_sorting_date(game)

    if upcoming_game?(game)
      [ 0, date || Date.new(9999, 12, 31), game.time.to_s ]
    else
      [ 1, -date.to_time.to_i, game.time.to_s ]
    end
  end

  def game_sorting_date(game)
    # Order by the same occurrence the card shows, not by the original start date.
    game.display_date_for_show || game.date
  end

  def local_upcoming_sort_key(game, city_name)
    [
      game_sorting_date(game) || Date.new(9999, 12, 31),
      proximity_sort_key(game, city_name),
      game.time.to_s
    ]
  end

  def proximity_sort_key(game, city_name)
    city = user_city_record(city_name)
    return Float::INFINITY unless city&.latitude && city&.longitude

    coords = game.court&.coordinates.to_s.split(",")
    return Float::INFINITY unless coords.length == 2

    haversine_distance(city.latitude.to_f, city.longitude.to_f, coords[0].to_f, coords[1].to_f)
  end

  def user_city_record(city_name)
    aliases = city_aliases_for(city_name)
    @user_city_record ||= City.where("lower(name) IN (?)", aliases).order(population: :desc).first
  end

  def haversine_distance(lat1, lon1, lat2, lon2)
    rad = Math::PI / 180
    dlat = (lat2 - lat1) * rad
    dlon = (lon2 - lon1) * rad
    a = Math.sin(dlat / 2)**2 + Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dlon / 2)**2
    6_371 * 2 * Math.asin(Math.sqrt(a))
  end

  def game_params
    params.require(:game).permit(:court_id, :kind, :recurring, :occurrences_per_week, :with_coach, :coach_id, :second_coach_id, :date, :time, :players_count, :skill_level, :sport, :surface, :environment, :prebooking_enabled, :urgent_player_search, :duration_minutes, :comment)
  end

  def display_date(game)
    nd = game.display_date_for_show || game.date
    nd ? nd.strftime("%Y-%m-%d") : (game.date.presence || "—")
  end

  def display_time(game)
    nt = game.next_time
    if nt.is_a?(String)
      nt.presence || "—"
    elsif nt.respond_to?(:strftime)
      nt.strftime("%H:%M")
    else
      "—"
    end
  end

  def game_badges(game)
    badges = []

    if game.respond_to?(:training?) && game.training?
      badges << { text: I18n.t("games.badges.training"),
                  classes: "inline-flex items-center rounded-full bg-violet-50 px-2 py-0.5 text-xs font-medium text-violet-700 mr-2" }
    end

    # sport badge (if game.sport present)
    if game.respond_to?(:sport) && game.sport.present?
      badges << { text: game.sport.to_s.titleize,
                  classes: "inline-flex items-center rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-800 mr-2" }
    end

    # surface (hard / clay / grass / artificial grass)
    if game.respond_to?(:surface_label) && game.surface_label.present?
      badges << { text: game.surface_label,
                  classes: "inline-flex items-center rounded-full bg-amber-50 px-2 py-0.5 text-xs font-medium text-amber-700 mr-2" }
    end

    # environment (indoor / outdoor)
    if game.respond_to?(:environment_label) && game.environment_label.present?
      badges << { text: game.environment_label,
                  classes: "inline-flex items-center rounded-full bg-sky-50 px-2 py-0.5 text-xs font-medium text-sky-700 mr-2" }
    end

    # required skill level (support several possible attribute names)
    skill_attr = %w[min_skill skill_level level].find { |a| game.respond_to?(a) && game.public_send(a).present? }
    if skill_attr
      lvl = game.public_send(skill_attr).to_s
      if User::SKILL_LEVELS.include?(lvl)
        badges << { text: lvl.titleize,
                    classes: "inline-flex items-center rounded-full bg-yellow-50 px-2 py-0.5 text-xs font-medium text-yellow-700 mr-2" }
      end
    end

    # with_coach / need coach
    if game.respond_to?(:with_coach) && game.with_coach?
      badges << { text: I18n.t("games.badges.with_coach"),
                  classes: "inline-flex items-center rounded-full bg-blue-50 px-2 py-0.5 text-xs font-medium text-blue-700 mr-2" }
    elsif game.respond_to?(:needs_coach) && game.needs_coach?
      badges << { text: I18n.t("games.badges.need_coach"),
                  classes: "inline-flex items-center rounded-full bg-blue-50/20 px-2 py-0.5 text-xs font-medium text-blue-700 mr-2" }
    end

    if game.respond_to?(:participations)
      required = game.required_players
      taken = game.spots_taken
      spots_left = game.spots_left
      badges << {
        text: I18n.t("games.badges.spots_left", count: spots_left, taken: taken, required: required),
        classes: "inline-flex items-center rounded-full bg-red-50 px-2 py-0.5 text-xs font-medium text-red-700 mr-2"
      }
    end

    # recurring / weekly
    if game.respond_to?(:recurring) && game.recurring?
      badges << { text: I18n.t("games.badges.weekly"),
                  classes: "inline-flex items-center rounded-full bg-green-50 px-2 py-0.5 text-xs font-medium text-green-700 mr-2" }
    end

    badges
  end

  def sanitized_game_params
    gp = game_params.to_h
    gp["date"] = gp["date"].presence
    gp["time"] = gp["time"].presence
    gp["recurring"] = ActiveModel::Type::Boolean.new.cast(gp["recurring"]) if gp.key?("recurring")
    gp["kind"] = gp["kind"].presence || "game" if gp.key?("kind")
    gp["with_coach"] = ActiveModel::Type::Boolean.new.cast(gp["with_coach"]) if gp.key?("with_coach")
    gp["urgent_player_search"] = ActiveModel::Type::Boolean.new.cast(gp["urgent_player_search"]) if gp.key?("urgent_player_search")
    gp["occurrences_per_week"] = gp["occurrences_per_week"].to_i if gp.key?("occurrences_per_week")
    gp["players_count"] = gp["players_count"].to_i if gp.key?("players_count")
    gp["sport"] = gp["sport"].presence if gp.key?("sport")
    gp["skill_level"] = gp["skill_level"].presence if gp.key?("skill_level")
    gp["surface"] = gp["surface"].presence if gp.key?("surface")
    gp["environment"] = gp["environment"].presence if gp.key?("environment")
    gp
  end

  def build_city_country_map(city_names)
    City.where(name: city_names)
      .pluck(:name, :country_code, :population)
      .group_by(&:first)
      .transform_values { |rows| rows.max_by { |(_, _, population)| population.to_i }[1] }
  end

  def normalize_location_params!(city_country_map)
    if params[:country_slug].present?
      params[:country] = country_code_for_slug(params[:country_slug], city_country_map)
    end

    if params[:city_slug].present?
      params[:city] = city_name_for_slug(params[:city_slug], params[:country], city_country_map)
    end

    params[:country] = effective_country_code(city_country_map)
  end

  def effective_country_code(city_country_map)
    params[:country].presence || city_country_map[params[:city].to_s]
  end

  def country_code_for_slug(country_slug, city_country_map)
    slug = country_slug.to_s
    # The country code itself keeps working as a slug: links minted before the
    # country had a name in COUNTRY_NAMES still resolve.
    city_country_map.values.uniq.find do |country_code|
      country_name_for(country_code).parameterize == slug || country_code.to_s.downcase == slug
    end
  end

  def city_name_for_slug(city_slug, country_code, city_country_map)
    city_country_map.keys.find do |city_name|
      next false if country_code.present? && city_country_map[city_name] != country_code

      city_name.to_s.parameterize == city_slug.to_s
    end
  end

  def canonical_games_path_for(city_country_map)
    query = request.query_parameters.except("commit", "country", "city", "country_slug", "city_slug")
    fallback_query = request.query_parameters.except("commit", "country_slug", "city_slug")
    country_code = effective_country_code(city_country_map)
    country_slug = country_code.present? ? country_name_for(country_code).parameterize : nil
    city_slug = params[:city].present? ? params[:city].to_s.parameterize : nil

    base_path =
      if country_slug.present?
        games_browse_path(country_slug: country_slug, city_slug: city_slug.presence)
      elsif params[:country].present? || params[:city].present?
        request.path
      else
        root_path
      end

    if country_slug.blank? && (params[:country].present? || params[:city].present?)
      return base_path if fallback_query.empty?

      uri = URI(base_path)
      uri.query = fallback_query.to_query
      return uri.to_s
    end

    return base_path if query.empty?

    uri = URI(base_path)
    uri.query = query.to_query
    uri.to_s
  end

  def games_meta_title_for(city_country_map)
    location = games_meta_location(city_country_map)
    sport = params[:sport].to_s.titleize.presence

    if location.present? && sport.present?
      I18n.t("games.meta.title.location_sport", sport: sport, location: location)
    elsif location.present?
      I18n.t("games.meta.title.location", location: location)
    elsif sport.present?
      I18n.t("games.meta.title.sport", sport: sport)
    else
      I18n.t("games.meta.title.default")
    end
  end

  def games_meta_description_for(city_country_map)
    location = games_meta_location(city_country_map)
    sport = params[:sport].to_s.downcase.presence

    if location.present? && sport.present?
      I18n.t("games.meta.description.location_sport", sport: sport, location: location)
    elsif location.present?
      I18n.t("games.meta.description.location", location: location)
    elsif sport.present?
      I18n.t("games.meta.description.sport", sport: sport)
    else
      I18n.t("games.meta.description.default")
    end
  end

  def games_meta_location(city_country_map)
    labels = []
    labels << params[:city] if params[:city].present?
    labels << country_name_for(effective_country_code(city_country_map)) if effective_country_code(city_country_map).present?
    labels.uniq.join(", ").presence
  end
end
