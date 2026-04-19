require "test_helper"

class ApplicationControllerTest < ActionDispatch::IntegrationTest
  test "shows locale suggestion on main host when country points to russian" do
    get root_url(host: "getcourt.co"), headers: { "CF-IPCountry" => "RU" }

    assert_response :success
    assert_select "#locale-suggestion", count: 1
    assert_includes response.body, "Похоже, вы говорите по-русски"
  end

  test "does not show locale suggestion on localized subdomain" do
    get root_url(host: "ru.getcourt.co"), headers: { "CF-IPCountry" => "RU" }

    assert_response :success
    assert_select "#locale-suggestion", count: 0
  end

  test "does not show locale suggestion when dismissed" do
    host! "getcourt.co"
    cookies[:locale_banner_dismissed] = "1"

    get root_path, headers: { "CF-IPCountry" => "RU" }

    assert_response :success
    assert_select "#locale-suggestion", count: 0
  end

  test "does not show locale suggestion after explicit preferred locale" do
    host! "getcourt.co"
    cookies[:preferred_locale] = "en"

    get root_path, headers: { "CF-IPCountry" => "RU" }

    assert_response :success
    assert_select "#locale-suggestion", count: 0
  end

  test "does not show locale suggestion to search crawlers" do
    get root_url(host: "getcourt.co"), headers: { "CF-IPCountry" => "RU", "User-Agent" => "Googlebot" }

    assert_response :success
    assert_select "#locale-suggestion", count: 0
  end
end
