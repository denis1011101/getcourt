class GamesController < ApplicationController
  include LocationFilters

  SEO_HOST = "https://getcourt.co".freeze

  before_action :handle_mark_not_happened, only: [ :show ]
  before_action :set_game, only: %i[show edit update destroy toggle_urgent_player_search]
  before_action :authorize_manage_game!, only: %i[edit update destroy toggle_urgent_player_search]
  skip_before_action :authenticate_user!, only: %i[index show]

  helper_method :display_date, :display_time, :game_badges

  def index
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
    @canonical_games_url = "#{SEO_HOST}#{canonical_path || request.path}"
    @games_meta_title = games_meta_title_for(city_country_map)
    @games_meta_description = games_meta_description_for(city_country_map)

    if params[:country].present?
      cities_in_country = cities_for_country(params[:country])
    end

    scoped_games = Game.includes(:court, :tournament, :participations, :prebooking_cancellations).order(:date, :time)
    scoped_games = scoped_games.where(sport: params[:sport]) if params[:sport].present?
    scoped_games = scoped_games.where(skill_level: params[:skill_level]) if params[:skill_level].present?

    if params[:country].present? && params[:city].blank?
      scoped_games = scoped_games.joins(:court).where(courts: { city_name: cities_in_country }) if cities_in_country.any?
    end

    if params[:city].present?
      scoped_games = scoped_games.joins(:court).where(courts: { city_name: params[:city] })
    end

    if params[:my_games].present? && current_user
      scoped_games = scoped_games.where(
        "games.user_id = :uid OR games.id IN (SELECT game_id FROM participations WHERE user_id = :uid)",
        uid: current_user.id
      )
    end

    if params[:with_spots].present? || current_user&.city_name.present?
      games = scoped_games.to_a

      if params[:with_spots].present?
        games = games.select do |game|
          required = game.players_count.to_i > 0 ? game.players_count.to_i : 4
          approved_count =
            if game.participations.loaded?
              game.participations.target.count(&:approved?)
            else
              game.participations.approved.count
            end

          approved_count < required
        end
      end

      if current_user&.city_name.present?
        user_city = current_user.city_name.downcase
        local, other = games.partition { |g| g.court&.city_name.to_s.downcase == user_city }
        games = local + other
      end

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
      redirect_to @game, notice: "Game was successfully created."
    else
      Rails.logger.warn "Game save failed: #{ @game.errors.full_messages.join('; ') }"
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    gp = sanitized_game_params
    if @game.update(gp)
      @game.ensure_prebookings_for_next_weeks if @game.prebooking_enabled?
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

  def toggle_urgent_player_search
    @game.update!(urgent_player_search: !@game.urgent_player_search?)
    state = @game.urgent_player_search? ? "enabled" : "disabled"
    redirect_to @game, notice: "Urgent player search #{state}."
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

  def authorize_manage_game!
    unless can_manage?(@game)
      head :forbidden
    end
  end

  def set_game
    @game = Game.find(params[:id])
  end

  def game_params
    params.require(:game).permit(:court_id, :recurring, :occurrences_per_week, :with_coach, :date, :time, :players_count, :skill_level, :sport, :prebooking_enabled, :urgent_player_search)
  end

  def display_date(game)
    nd = game.display_date_for_show
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

    # sport badge (if game.sport present)
    if game.respond_to?(:sport) && game.sport.present?
      badges << { text: game.sport.to_s.titleize,
                  classes: "inline-flex items-center rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-800 mr-2" }
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
      badges << { text: "With coach",
                  classes: "inline-flex items-center rounded-full bg-blue-50 px-2 py-0.5 text-xs font-medium text-blue-700 mr-2" }
    elsif game.respond_to?(:needs_coach) && game.needs_coach?
      badges << { text: "Need coach",
                  classes: "inline-flex items-center rounded-full bg-blue-50/20 px-2 py-0.5 text-xs font-medium text-blue-700 mr-2" }
    end

    if game.respond_to?(:participations)
      required = (game.respond_to?(:players_count) && game.players_count.to_i > 0) ? game.players_count.to_i : 4
      approved_participations = game.participations.respond_to?(:approved) ? game.participations.approved : game.participations
      taken = approved_participations.size
      spots_left = required - taken
      badges << {
        text: "#{spots_left} spot#{'s' if spots_left != 1} left — #{taken}/#{required}",
        classes: "inline-flex items-center rounded-full bg-red-50 px-2 py-0.5 text-xs font-medium text-red-700 mr-2"
      }
    end

    # recurring / weekly
    if game.respond_to?(:recurring) && game.recurring?
      badges << { text: "Weekly",
                  classes: "inline-flex items-center rounded-full bg-green-50 px-2 py-0.5 text-xs font-medium text-green-700 mr-2" }
    end

    badges
  end

  def sanitized_game_params
    gp = game_params.to_h
    gp["date"] = gp["date"].presence
    gp["time"] = gp["time"].presence
    gp["recurring"] = ActiveModel::Type::Boolean.new.cast(gp["recurring"]) if gp.key?("recurring")
    gp["with_coach"] = ActiveModel::Type::Boolean.new.cast(gp["with_coach"]) if gp.key?("with_coach")
    gp["urgent_player_search"] = ActiveModel::Type::Boolean.new.cast(gp["urgent_player_search"]) if gp.key?("urgent_player_search")
    gp["occurrences_per_week"] = gp["occurrences_per_week"].to_i if gp.key?("occurrences_per_week")
    gp["players_count"] = gp["players_count"].to_i if gp.key?("players_count")
    gp["sport"] = gp["sport"].presence if gp.key?("sport")
    gp["skill_level"] = gp["skill_level"].presence if gp.key?("skill_level")
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
    city_country_map.values.uniq.find do |country_code|
      country_name_for(country_code).parameterize == country_slug.to_s
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
      "#{sport} games in #{location} — GetCourt"
    elsif location.present?
      "Tennis games in #{location} — GetCourt"
    elsif sport.present?
      "#{sport} games near you — GetCourt"
    else
      "GetCourt — Find Tennis, Padel & Squash Games Near You"
    end
  end

  def games_meta_description_for(city_country_map)
    location = games_meta_location(city_country_map)
    sport = params[:sport].to_s.downcase.presence

    if location.present? && sport.present?
      "Find #{sport} games in #{location}. Join a match or create your own on GetCourt."
    elsif location.present?
      "Find tennis, padel, table tennis and squash games in #{location}. Join a match or create your own on GetCourt."
    elsif sport.present?
      "Find #{sport} games near you. Join a match or create your own on GetCourt."
    else
      "Join or create tennis, padel, table tennis and squash games. Find players and courts near you. Quick setup with Telegram reminders."
    end
  end

  def games_meta_location(city_country_map)
    labels = []
    labels << params[:city] if params[:city].present?
    labels << country_name_for(effective_country_code(city_country_map)) if effective_country_code(city_country_map).present?
    labels.uniq.join(", ").presence
  end
end
