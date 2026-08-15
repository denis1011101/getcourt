module Mcp
  # Минимальный MCP-сервер поверх JSON-RPC 2.0. Инструментов два и оба только на
  # чтение, поэтому городить зависимость ради этого незачем: весь протокол здесь —
  # initialize, tools/list и tools/call.
  #
  # Записывающие инструменты (создать игру, присоединиться) сюда не добавлять
  # походя: у них сразу встаёт вопрос авторизации от имени пользователя, а токен
  # тут один на всех.
  class Server
    JSONRPC_VERSION = "2.0".freeze
    LATEST_PROTOCOL = "2025-06-18".freeze
    SUPPORTED_PROTOCOLS = [ LATEST_PROTOCOL, "2025-03-26", "2024-11-05" ].freeze

    PARSE_ERROR = -32700
    INVALID_REQUEST = -32600
    METHOD_NOT_FOUND = -32601
    INVALID_PARAMS = -32602
    INTERNAL_ERROR = -32603

    TOOLS = [
      {
        name: "search_games",
        description: "Search for upcoming GetCourt games. Filters by city, sport, skill level, " \
                     "date range and whether the game still has free spots.",
        inputSchema: {
          type: "object",
          properties: {
            city: { type: "string", description: "City name as it appears on the court, e.g. \"Belgrade\"." },
            sport: { type: "string", description: "Sport name, e.g. \"Tennis\", \"Padel\", \"Squash\"." },
            skill_level: { type: "string", description: "Skill level filter, e.g. \"Beginner\"." },
            with_spots: { type: "boolean", description: "Only games that still have a free spot." },
            urgent: { type: "boolean", description: "Only games whose organiser flagged an urgent player search." },
            from: { type: "string", description: "Earliest date, ISO 8601 (YYYY-MM-DD)." },
            to: { type: "string", description: "Latest date, ISO 8601 (YYYY-MM-DD)." },
            limit: { type: "integer", description: "How many games to return (1-100, default 25)." }
          },
          required: []
        }
      },
      {
        name: "get_game",
        description: "Fetch one GetCourt game by its numeric id.",
        inputSchema: {
          type: "object",
          properties: { id: { type: "integer", description: "Game id." } },
          required: [ "id" ]
        }
      }
    ].freeze

    def initialize(host:)
      @host = host
    end

    # Возвращает хеш-ответ или nil, если пришло уведомление — на уведомления
    # JSON-RPC отвечать не положено.
    def call(message)
      return error_response(nil, INVALID_REQUEST, "Expected a JSON-RPC object") unless message.is_a?(Hash)

      id = message["id"]
      method = message["method"].to_s
      params = message["params"].is_a?(Hash) ? message["params"] : {}

      return nil if id.nil? && method.start_with?("notifications/")

      case method
      when "initialize" then result_response(id, initialize_result(params))
      when "ping" then result_response(id, {})
      when "tools/list" then result_response(id, { tools: TOOLS })
      when "tools/call" then result_response(id, call_tool(params))
      else error_response(id, METHOD_NOT_FOUND, "Unknown method: #{method}")
      end
    rescue InvalidParams => e
      error_response(message.is_a?(Hash) ? message["id"] : nil, INVALID_PARAMS, e.message)
    rescue => e
      Rails.logger.error("[Mcp::Server] #{e.class}: #{e.message}")
      error_response(message.is_a?(Hash) ? message["id"] : nil, INTERNAL_ERROR, "Internal error")
    end

    class InvalidParams < StandardError; end

    private

    def initialize_result(params)
      requested = params["protocolVersion"].to_s

      {
        protocolVersion: SUPPORTED_PROTOCOLS.include?(requested) ? requested : LATEST_PROTOCOL,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "getcourt", version: "1.0.0" }
      }
    end

    def call_tool(params)
      name = params["name"].to_s
      arguments = params["arguments"].is_a?(Hash) ? params["arguments"] : {}

      payload =
        case name
        when "search_games" then search_games(arguments)
        when "get_game" then get_game(arguments)
        else raise InvalidParams, "Unknown tool: #{name}"
        end

      # Текстовый content понимают все клиенты; structuredContent поддержан не везде.
      { content: [ { type: "text", text: JSON.pretty_generate(payload) } ], isError: false }
    end

    def search_games(arguments)
      games = Games::Search.new(scope: visible_games)
        .sport(arguments["sport"])
        .skill_level(arguments["skill_level"])
        .in_cities(arguments["city"])
        .urgent_only(arguments["urgent"])
        .from_date(arguments["from"])
        .to_date(arguments["to"])
        .upcoming_only(true)
        .ordered
        .to_a

      games = Games::Search.with_spots(games) if arguments["with_spots"]
      games = games.first(Games::Search.limit_for(arguments["limit"]))

      { games: Games::Serializer.new(games, host: @host).as_json }
    end

    def get_game(arguments)
      id = arguments["id"]
      raise InvalidParams, "id is required" if id.blank?

      game = visible_games.find_by(id: id)
      raise InvalidParams, "Game #{id} not found" unless game

      { game: Games::Serializer.new([ game ], host: @host).as_json.first }
    end

    def visible_games
      Game.joins(:court).merge(Court.approved)
    end

    def result_response(id, result)
      { jsonrpc: JSONRPC_VERSION, id: id, result: result }
    end

    def error_response(id, code, message)
      { jsonrpc: JSONRPC_VERSION, id: id, error: { code: code, message: message } }
    end
  end
end
