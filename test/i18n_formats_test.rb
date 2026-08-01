require "test_helper"

class I18nFormatsTest < ActiveSupport::TestCase
  EXPECTED_FORMATS = {
    "en" => { date: "2026-08-02", time: "02 Aug 23:54" },
    "ru" => { date: "02.08.2026", time: "02 авг., 23:54" },
    "es" => { date: "02/08/2026", time: "02/08/2026 23:54" }
  }.freeze

  test "formats dates and short times for every web locale" do
    timestamp = Time.zone.local(2026, 8, 2, 23, 54)
    assert_equal User::WEB_LOCALES.sort, EXPECTED_FORMATS.keys.sort

    EXPECTED_FORMATS.each do |locale, expected|
      assert_equal expected[:date], I18n.l(timestamp.to_date, locale: locale)
      assert_equal expected[:time], I18n.l(timestamp, format: :short, locale: locale)
    end
  end
end
