require "test_helper"

class Weather::IconsTest < ActiveSupport::TestCase
  test "maps weather conditions to icons" do
    assert_equal "⛈️", Weather::Icons.for("THUNDERSTORM")
    assert_equal "❄️", Weather::Icons.for("SNOW")
    assert_equal "🌧️", Weather::Icons.for("RAIN_SHOWERS")
    assert_equal "💨", Weather::Icons.for("WINDY")
    assert_equal "⛅", Weather::Icons.for("PARTLY_CLOUDY")
    assert_equal "☀️", Weather::Icons.for("CLEAR")
    assert_equal "🌡️", Weather::Icons.for("UNKNOWN")
  end
end
