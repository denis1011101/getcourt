require "test_helper"

class Weather::GoogleForecastTest < ActiveSupport::TestCase
  test "returns the hourly forecast for the game time" do
    travel_to Time.zone.local(2026, 8, 1, 12, 0, 0) do
      game = outdoor_game(date: Date.current + 1.day, time: "15:00")
      target_time = game.start_at_for_ui
      payload = {
        "forecastHours" => [
          {
            "interval" => {
              "startTime" => target_time.beginning_of_hour.iso8601,
              "endTime" => (target_time.beginning_of_hour + 1.hour).iso8601
            },
            "temperature" => { "degrees" => 18.6 },
            "weatherCondition" => { "type" => "PARTLY_CLOUDY", "description" => { "text" => "Partly cloudy" } },
            "precipitation" => { "probability" => { "percent" => 40 } }
          }
        ]
      }
      requested_uri = nil

      with_env("GOOGLE_WEATHER_API_KEY" => "weather-key") do
        stub_singleton(Weather::GoogleForecast, :fetch_json, ->(uri) { requested_uri = uri; payload }) do
          reading = Weather::GoogleForecast.for_game(game)

          assert_in_delta 18.6, reading.temperature_c
          assert_equal "PARTLY_CLOUDY", reading.condition_type
          assert_equal "Partly cloudy", reading.description
          assert_equal 40, reading.precipitation_percent
          assert_includes requested_uri.path, "forecast/hours:lookup"
          assert_equal "METRIC", URI.decode_www_form(requested_uri.query).to_h["unitsSystem"]
        end
      end
    end
  end

  test "uses one daily forecast request for a distant game" do
    travel_to Time.zone.local(2026, 8, 1, 12, 0, 0) do
      game = outdoor_game(date: Date.current + 9.days, time: "15:00")
      target_time = game.start_at_for_ui
      payload = {
        "forecastDays" => [
          {
            "interval" => {
              "startTime" => (target_time - 8.hours).iso8601,
              "endTime" => (target_time + 16.hours).iso8601
            },
            "daytimeForecast" => {
              "interval" => {
                "startTime" => (target_time - 8.hours).iso8601,
                "endTime" => (target_time + 4.hours).iso8601
              },
              "weatherCondition" => { "type" => "CLEAR", "description" => { "text" => "Clear" } },
              "precipitation" => { "probability" => { "percent" => 5 } }
            },
            "maxTemperature" => { "degrees" => 24.5 },
            "minTemperature" => { "degrees" => 12.0 }
          }
        ]
      }
      requested_uris = []

      with_env("GOOGLE_WEATHER_API_KEY" => "weather-key") do
        stub_singleton(Weather::GoogleForecast, :fetch_json, ->(uri) { requested_uris << uri; payload }) do
          reading = Weather::GoogleForecast.for_game(game)

          assert_in_delta 24.5, reading.temperature_c
          assert_equal "CLEAR", reading.condition_type
          assert_equal 1, requested_uris.size
          assert_includes requested_uris.first.path, "forecast/days:lookup"
          query = URI.decode_www_form(requested_uris.first.query).to_h
          assert_equal "10", query["pageSize"]
          assert_equal "METRIC", query["unitsSystem"]
        end
      end
    end
  end

  test "returns nil when no API key is configured" do
    game = outdoor_game(date: Date.current + 1.day, time: "15:00")

    with_env("GOOGLE_WEATHER_API_KEY" => "", "GOOGLE_MAPS_API_KEY" => "") do
      assert_nil Weather::GoogleForecast.for_game(game)
    end
  end

  test "returns nil for a game beyond the forecast horizon" do
    game = outdoor_game(date: Date.current + 11.days, time: "15:00")

    assert_nil Weather::GoogleForecast.for_game(game)
  end

  test "returns nil for an indoor game" do
    game = outdoor_game(date: Date.current + 1.day, time: "15:00")
    game.update_columns(environment: "indoor")

    assert_nil Weather::GoogleForecast.for_game(game)
  end

  test "returns nil when the court has no coordinates" do
    game = outdoor_game(date: Date.current + 1.day, time: "15:00")
    game.court.update_columns(coordinates: nil)

    assert_nil Weather::GoogleForecast.for_game(game)
  end

  test "does not cache a miss from a shortened timeout" do
    travel_to Time.zone.local(2026, 8, 1, 12, 0, 0) do
      game = outdoor_game(date: Date.current + 1.day, time: "15:00")
      writes = []
      cache = Object.new
      cache.define_singleton_method(:read) { |_| nil }
      cache.define_singleton_method(:write) { |*args, **kwargs| writes << [ args, kwargs ] }

      stub_singleton(Rails, :cache, -> { cache }) do
        stub_singleton(Weather::GoogleForecast, :fetch_reading, ->(*) { nil }) do
          assert_nil Weather::GoogleForecast.for_game(game, timeout: { open: 2, read: 3 })
          assert_empty writes

          assert_nil Weather::GoogleForecast.for_game(game)
          assert_equal 1, writes.size
          assert_equal :none, writes.first.first.second
        end
      end
    end
  end

  private
    def outdoor_game(date:, time:)
      game = games(:one)
      game.court.update_columns(coordinates: "55.75,37.62")
      game.update_columns(date: date, time: time, recurring: false, environment: nil)
      game.reload
    end

    def with_env(vars)
      old = vars.keys.index_with { |key| ENV[key] }
      vars.each { |key, value| ENV[key] = value }
      yield
    ensure
      old.each { |key, value| value.nil? ? ENV.delete(key) : ENV.store(key, value) }
    end
end
