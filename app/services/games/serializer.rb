module Games
  # Публичное представление игры: ровно то, что и так видно на странице игры.
  # Ничего про участников — ни имён, ни email, ни telegram_chat_id: в API уходит
  # только «сколько занято из скольких».
  class Serializer
    def initialize(games, host:)
      @games = Array(games)
      @host = host
      @country_codes = City.country_codes_for(@games.filter_map { |game| game.court&.city_name })
    end

    def as_json
      @games.map { |game| game_json(game) }
    end

    private

    def game_json(game)
      {
        id: game.id,
        # Для повторяющейся игры показанное вхождение считается на лету —
        # см. display_date_for_show, единственный источник правды после B-32.
        date: game.display_date_for_show&.iso8601,
        time: game.time&.strftime("%H:%M"),
        duration_minutes: game.duration_minutes,
        recurring: game.recurring?,
        sport: game.sport,
        skill_level: game.skill_level,
        surface: game.surface,
        environment: game.environment,
        kind: game.kind,
        with_coach: game.with_coach?,
        urgent_player_search: game.urgent_player_search?,
        comment: game.comment.presence,
        players: {
          taken: game.spots_taken,
          total: game.required_players,
          spots_left: game.spots_left
        },
        court: court_json(game.court),
        url: "#{@host}/games/#{game.id}"
      }
    end

    def court_json(court)
      return nil unless court

      latitude, longitude = court.coordinates_pair

      {
        id: court.id,
        name: court.name,
        city: court.city_name,
        country_code: @country_codes[court.city_name.to_s],
        latitude: latitude,
        longitude: longitude,
        indoor: court.indoor?,
        outdoor: court.outdoor?,
        free: court.free?,
        url: "#{@host}/courts/#{court.id}"
      }
    end
  end
end
