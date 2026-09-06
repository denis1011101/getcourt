require "test_helper"

# Лимиты живут в Rack::Attack, а в тестовой среде кэш — :null_store, поэтому
# счётчики никуда не пишутся. На время теста подменяем хранилище на память.
class LoginCodeThrottlingTest < ActionDispatch::IntegrationTest
  setup do
    @previous_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    @user = User.create!(
      email: "throttled-login@example.com",
      require_verification: true,
      preferred_login_via: "email"
    )
    @code = @user.generate_login_code!(via: "email")
  end

  teardown do
    Rack::Attack.cache.store = @previous_store
    @user&.destroy
  end

  test "wrong codes for one email run into the limit" do
    10.times { attempt(code: wrong_code) }
    assert_response :unprocessable_entity

    attempt(code: wrong_code)
    assert_response :too_many_requests

    # Правильный код тоже упирается в лимит: иначе перебор просто доводят до конца.
    attempt(code: @code)
    assert_response :too_many_requests
    assert_nil session[:user_id]
  end

  # Rails узнаёт тот же маршрут во всех этих написаниях, включая закодированную
  # букву в расширении и произвольный суффикс формата.
  test "the same limit covers every spelling of the route Rails accepts" do
    paths = [
      "/sign_in/verify",
      "/sign_in/verify.html",
      "/sign_in/verify.ht%6dl",
      "/sign_in/verify.html-foo",
      "/sign_in/verify/",
      "//sign_in/verify",
      "/sign_in//verify"
    ]
    paths.cycle.first(11).each { |path| attempt(code: wrong_code, path: path) }

    assert_response :too_many_requests
  end

  # Обрезанное по лимиту тело не разбирается, и раньше попытка проходила мимо
  # счётчика: контроллер-то читает тело целиком.
  test "an oversized JSON body does not buy extra attempts" do
    padding = "x" * (70 * 1024)
    11.times do
      post "/sign_in/verify",
           params: { email: @user.email, code: wrong_code, padding: padding }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }
    end

    assert_response :too_many_requests
  end

  # Rails берёт почту из query поверх тела; счётчик должен смотреть туда же,
  # иначе подставные адреса в теле уводят попытки в чужие корзины.
  test "the counter follows the email Rails actually signs in with" do
    11.times do |index|
      post "/sign_in/verify?email=#{CGI.escape(@user.email)}",
           params: { email: "decoy-#{index}@example.com", code: wrong_code }
    end

    assert_response :too_many_requests
  end

  test "an email sent as JSON counts towards the same limit" do
    11.times do
      post "/sign_in/verify",
           params: { email: @user.email, code: wrong_code }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }
    end

    assert_response :too_many_requests
  end

  # На подтверждении токена почты в запросе нет, поэтому там работает лимит на
  # адрес; сам подбор кода дополнительно упирается в счётчик промахов.
  test "confirming token ownership runs into the address limit" do
    owner = User.create!(email: "token-confirm-throttle@example.com", email_verified_at: Time.current)
    post session_url, params: { email: owner.email }

    31.times { post confirm_api_token_url, params: { code: "0000" } }

    assert_response :too_many_requests
  ensure
    owner&.destroy
  end

  test "one address cannot spray codes across many accounts" do
    31.times do |index|
      post "/sign_in/verify", params: { email: "sprayed-#{index}@example.com", code: wrong_code }
    end

    assert_response :too_many_requests
  end

  private

  def attempt(code:, path: "/sign_in/verify")
    post path, params: { email: @user.email, code: code }
  end

  # Настоящий код случайный, поэтому «заведомо неверный» выбираем от него.
  def wrong_code
    @code == "0000" ? "1111" : "0000"
  end
end
