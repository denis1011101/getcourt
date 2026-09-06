# Rack::Attack is inserted into the middleware stack by its railtie.
#
# Ahoy exposes public, unauthenticated endpoints (/ahoy/visits, /ahoy/events)
# when Ahoy.api is enabled. Throttle them per IP so a client can't flood the
# database with arbitrary events. See https://github.com/ankane/ahoy#throttling
class Rack::Attack
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
    request.post? && request.path == "/sign_in/verify"
  end

  throttle("login_code/email", limit: 10, period: 15.minutes) do |request|
    request.params["email"].to_s.strip.downcase.presence if login_code_attempt?(request)
  end

  throttle("login_code/ip", limit: 30, period: 1.hour) do |request|
    request.ip if login_code_attempt?(request)
  end
end
