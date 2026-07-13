require "test_helper"

class LocaleControllerTest < ActionDispatch::IntegrationTest
  test "sets preferred locale cookie and redirects to locale host" do
    get set_locale_url(locale: "ru")

    assert_redirected_to "https://ru.getcourt.co/"
    assert_equal "ru", cookies[:preferred_locale]
  end

  test "stores an authenticated user's explicit locale" do
    email = "locale_preference_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: email }
    user = User.find_by!(email: email)

    get set_locale_url(locale: "es")

    assert_redirected_to "https://es.getcourt.co/"
    assert_equal "es", user.reload.locale
  ensure
    user&.destroy
  end

  test "sets preferred locale cookie for getcourt subdomains" do
    get set_locale_url(locale: "en", host: "ru.getcourt.co")

    assert_redirected_to "https://getcourt.co/"
    assert_match(/domain=.*getcourt\.co/i, response.headers["Set-Cookie"])
  end

  test "redirects with safe return path" do
    get set_locale_url(locale: "ru", return_to: "/games")

    assert_redirected_to "https://ru.getcourt.co/games"
  end

  test "sanitizes external return path" do
    get set_locale_url(locale: "ru", return_to: "//evil.com")

    assert_redirected_to "https://ru.getcourt.co/"
  end

  test "invalid locale is not routed" do
    get "/locale/de"

    assert_response :not_found
  end

  test "dismisses locale banner server side" do
    post dismiss_locale_banner_url(host: "getcourt.co", return_to: "/games")

    assert_redirected_to "/games"
    assert_equal "1", cookies[:locale_banner_dismissed]
    assert_match(/domain=.*getcourt\.co/i, response.headers["Set-Cookie"])
  end
end
