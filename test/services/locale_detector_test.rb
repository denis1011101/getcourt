require "test_helper"

class LocaleDetectorTest < ActiveSupport::TestCase
  Request = Struct.new(:subdomains, :headers)

  test "subdomain has priority over everything" do
    request = build_request(subdomains: [ "ru" ], headers: { "CF-IPCountry" => "ES", "Accept-Language" => "es-MX,en;q=0.9" })

    assert_equal "ru", LocaleDetector.call(request, { preferred_locale: "es" })
  end

  test "unsupported subdomain falls through to cookie" do
    request = build_request(subdomains: [ "api" ], headers: { "CF-IPCountry" => "RU" })

    assert_equal "es", LocaleDetector.call(request, { preferred_locale: "es" })
  end

  test "cookie wins over cloudflare country" do
    request = build_request(headers: { "CF-IPCountry" => "RU" })

    assert_equal "es", LocaleDetector.call(request, { preferred_locale: "es" })
  end

  test "cloudflare country maps to locale" do
    assert_equal "ru", LocaleDetector.call(build_request(headers: { "CF-IPCountry" => "RU" }), {})
    assert_equal "es", LocaleDetector.call(build_request(headers: { "CF-IPCountry" => "ES" }), {})
    assert_equal "en", LocaleDetector.call(build_request(headers: { "CF-IPCountry" => "DE" }), {})
  end

  test "accept language maps region tag to locale" do
    request = build_request(headers: { "Accept-Language" => "ru-RU,en;q=0.9" })

    assert_equal "ru", LocaleDetector.call(request, {})
  end

  test "accept language respects quality order" do
    request = build_request(headers: { "Accept-Language" => "ru-RU;q=0.5,es-MX;q=0.9,en;q=0.1" })

    assert_equal "es", LocaleDetector.call(request, {})
  end

  test "falls back to default locale" do
    assert_equal "en", LocaleDetector.call(build_request, {})
  end

  test "falls back to default locale for unsupported accept language" do
    request = build_request(headers: { "Accept-Language" => "fr,de;q=0.9,ja;q=0.8" })

    assert_equal "en", LocaleDetector.call(request, {})
  end

  private

  def build_request(subdomains: [], headers: {})
    Request.new(subdomains, headers)
  end
end
