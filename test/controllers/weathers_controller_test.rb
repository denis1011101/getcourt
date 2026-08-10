require "test_helper"

class WeathersControllerTest < ActionDispatch::IntegrationTest
  test "renders an empty public frame when forecast is unavailable" do
    game = games(:one)

    stub_singleton(Weather::GoogleForecast, :for_game, ->(_) { nil }) do
      get game_weather_path(game)
    end

    assert_response :success
    assert_select "turbo-frame#weather_game_#{game.id}", count: 1 do
      assert_select "span", count: 0
    end
  end

  test "renders the weather badge" do
    game = games(:one)
    reading = Weather::GoogleForecast::Reading.new(
      temperature_c: 18.6,
      condition_type: "PARTLY_CLOUDY",
      description: "Partly cloudy",
      precipitation_percent: 40
    )

    stub_singleton(Weather::GoogleForecast, :for_game, ->(_) { reading }) do
      get game_weather_path(game)
    end

    assert_response :success
    assert_select "turbo-frame#weather_game_#{game.id} span", text: /⛅ 19°.*40%/
  end
end
