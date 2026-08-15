class McpController < Api::BaseController
  before_action :authenticate_mcp!

  # Streamable HTTP: клиент шлёт JSON-RPC пакет POST-ом и получает JSON в ответ.
  # Пакет бывает батчем — массивом сообщений; уведомления ответа не имеют, и если
  # в батче одни уведомления, по спецификации возвращается 202 с пустым телом.
  def create
    payload = parse_payload
    return render(json: parse_error, status: :bad_request) if payload == :invalid

    if payload.is_a?(Array)
      return render(json: invalid_request, status: :bad_request) if payload.empty?

      responses = payload.filter_map { |message| server.call(message) }
      responses.any? ? render(json: responses) : head(:accepted)
    else
      response_body = server.call(payload)
      response_body ? render(json: response_body) : head(:accepted)
    end
  end

  private

  def server
    @server ||= Mcp::Server.new(host: ENV.fetch("APP_HOST", "https://getcourt.co"))
  end

  def parse_payload
    JSON.parse(request.raw_post)
  rescue JSON::ParserError
    :invalid
  end

  def parse_error
    { jsonrpc: Mcp::Server::JSONRPC_VERSION, id: nil,
      error: { code: Mcp::Server::PARSE_ERROR, message: "Parse error" } }
  end

  def invalid_request
    { jsonrpc: Mcp::Server::JSONRPC_VERSION, id: nil,
      error: { code: Mcp::Server::INVALID_REQUEST, message: "Invalid request" } }
  end

  # Токен один на всех: инструменты только читают публичные данные, но эндпоинт
  # закрыт, чтобы его не звали кто попало. Без заданного MCP_TOKEN сервер
  # выключен целиком — иначе забытая переменная окружения открыла бы его всем.
  def authenticate_mcp!
    expected = ENV["MCP_TOKEN"].to_s
    return head(:not_found) if expected.blank?

    provided = request.headers["Authorization"].to_s.delete_prefix("Bearer ").strip
    return if provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided, expected)

    head :unauthorized
  end
end
