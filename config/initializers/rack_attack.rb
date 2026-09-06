# Rack::Attack is inserted into the middleware stack by its railtie.
#
# Ahoy exposes public, unauthenticated endpoints (/ahoy/visits, /ahoy/events)
# when Ahoy.api is enabled. Throttle them per IP so a client can't flood the
# database with arbitrary events. See https://github.com/ankane/ahoy#throttling
class Rack::Attack
  # Тело запроса читаем сами, поэтому ограничиваем: разбирать мегабайты ради
  # одного поля незачем.
  JSON_BODY_LIMIT = 64.kilobytes
  UNPARSED_EMAIL = "unparsed".freeze

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
  #
  # Тот же счётчик держит подтверждение владения аккаунтом перед выдачей токена:
  # код там тот же самый.
  CODE_ACTIONS = [ %w[sessions check], %w[api_tokens confirm] ].freeze

  # Сравнивать путь строкой бесполезно: Rails узнаёт тот же маршрут и в
  # /sign_in/verify.html, и в /sign_in/verify.ht%6dl, и в /sign_in/verify.html-foo,
  # и с лишними или хвостовыми слэшами. Поэтому спрашиваем сам роутер.
  def self.code_attempt?(request)
    return false unless request.post?

    route = recognized_route(request)
    route.present? && CODE_ACTIONS.include?([ route[:controller], route[:action] ])
  end

  def self.recognized_route(request)
    request.env.fetch("getcourt.recognized_route") do
      request.env["getcourt.recognized_route"] =
        begin
          Rails.application.routes.recognize_path(request.path, method: request.request_method)
        rescue StandardError
          nil
        end
    end
  end

  # Порядок тот же, что у Rails: query перекрывает тело, а не наоборот, как в
  # Rack::Request#params. Иначе почту в счётчике и почту, по которой контроллер
  # ищет пользователя, можно развести и перебирать код мимо лимита.
  def self.attempt_email(request)
    email = query_email(request)
    email = body_email(request) if email.blank?
    email.is_a?(String) ? email.strip.downcase.presence : nil
  end

  def self.query_email(request)
    request.GET["email"]
  rescue StandardError
    nil
  end

  def self.body_email(request)
    return json_body_email(request) if request.media_type.to_s.include?("json")

    request.POST["email"]
  rescue StandardError
    UNPARSED_EMAIL
  end

  # Тело читаем сами, поэтому его размер приходится ограничивать. Всё, что не
  # разобралось, попадает в общий счётчик: пропустить такую попытку — значит
  # отдать лимит любому, кто добавит в JSON лишнее поле подлиннее.
  def self.json_body_email(request)
    request.body.rewind
    body = request.body.read(JSON_BODY_LIMIT + 1).to_s
    request.body.rewind
    return UNPARSED_EMAIL if body.bytesize > JSON_BODY_LIMIT

    parsed = JSON.parse(body)
    parsed.is_a?(Hash) ? parsed["email"] : UNPARSED_EMAIL
  rescue JSON::ParserError, IOError, ArgumentError
    UNPARSED_EMAIL
  end

  throttle("login_code/email", limit: 10, period: 15.minutes) do |request|
    attempt_email(request) if code_attempt?(request)
  end

  throttle("login_code/ip", limit: 30, period: 1.hour) do |request|
    request.ip if code_attempt?(request)
  end
end
