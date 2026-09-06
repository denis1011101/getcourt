# Rack::Attack is inserted into the middleware stack by its railtie.
#
# Ahoy exposes public, unauthenticated endpoints (/ahoy/visits, /ahoy/events)
# when Ahoy.api is enabled. Throttle them per IP so a client can't flood the
# database with arbitrary events. See https://github.com/ankane/ahoy#throttling
class Rack::Attack
  # Тело запроса читаем сами, поэтому ограничиваем: разбирать мегабайты ради
  # одного поля незачем.
  JSON_BODY_LIMIT = 4096

  throttle("ahoy/ip", limit: 20, period: 20.seconds) do |request|
    request.ip if request.path.start_with?("/ahoy")
  end

  throttle("court_suggestions/ip", limit: 5, period: 1.hour) do |request|
    if request.post? && request.path.match?(%r{\A/courts/\d+/suggestions\z})
      request.ip
    end
  end

  # Публичная JSON-выдача игр и MCP-эндпоинт: оба без сессии, оба бьют в базу.
  # MCP-клиент за один вопрос делает несколько вызовов подряд, поэтому лимит выше.
  throttle("api/ip", limit: 60, period: 1.minute) do |request|
    request.ip if request.path.start_with?("/api/")
  end

  throttle("mcp/ip", limit: 120, period: 1.minute) do |request|
    request.ip if request.path == "/mcp"
  end

  # Код входа четырёхзначный, живёт 15 минут, и неудачная попытка его не гасит:
  # без лимита перебрать десять тысяч вариантов — вопрос нескольких минут, и
  # проверка кода превращается в формальность. Лимит на почту закрывает подбор
  # к конкретному аккаунту, лимит на адрес — веерный перебор по многим почтам.
  def self.login_code_attempt?(request)
    return false unless request.post?

    # Rails узнаёт маршрут и в /sign_in/verify.html, и с лишними или хвостовыми
    # слэшами, поэтому сравнивать сырой путь нельзя: любая из этих форм проходила
    # мимо лимита.
    path = request.path.to_s.squeeze("/").sub(/\.[a-z0-9]+\z/i, "").chomp("/")
    path == "/sign_in/verify"
  end

  # Форму отправляют и как JSON: Rails разберёт такое тело и достанет из него
  # почту, а Rack::Request#params видит только query и form-data.
  def self.login_code_email(request)
    email = request.params["email"]
    email = json_body_email(request) if email.blank? && request.media_type.to_s.include?("json")
    email.to_s.strip.downcase.presence
  end

  def self.json_body_email(request)
    request.body.rewind
    body = request.body.read(JSON_BODY_LIMIT)
    request.body.rewind
    parsed = JSON.parse(body.to_s)
    parsed["email"] if parsed.is_a?(Hash)
  rescue JSON::ParserError, IOError
    nil
  end

  throttle("login_code/email", limit: 10, period: 15.minutes) do |request|
    login_code_email(request) if login_code_attempt?(request)
  end

  throttle("login_code/ip", limit: 30, period: 1.hour) do |request|
    request.ip if login_code_attempt?(request)
  end
end
