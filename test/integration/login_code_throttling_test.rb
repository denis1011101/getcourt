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
    10.times { attempt(code: "0000") }
    assert_response :unprocessable_entity

    attempt(code: "0000")
    assert_response :too_many_requests

    # Правильный код тоже упирается в лимит: иначе перебор просто доводят до конца.
    attempt(code: @code)
    assert_response :too_many_requests
    assert_nil session[:user_id]
  end

  test "the same limit covers the route with a format and stray slashes" do
    [ "/sign_in/verify.html", "/sign_in/verify/", "//sign_in/verify", "/sign_in/verify" ].cycle.first(11).each do |path|
      attempt(code: "0000", path: path)
    end

    assert_response :too_many_requests
  end

  test "an email sent as JSON counts towards the same limit" do
    11.times do
      post "/sign_in/verify",
           params: { email: @user.email, code: "0000" }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }
    end

    assert_response :too_many_requests
  end

  test "one address cannot spray codes across many accounts" do
    31.times do |index|
      post "/sign_in/verify", params: { email: "sprayed-#{index}@example.com", code: "0000" }
    end

    assert_response :too_many_requests
  end

  private

  def attempt(code:, path: "/sign_in/verify")
    post path, params: { email: @user.email, code: code }
  end
end
