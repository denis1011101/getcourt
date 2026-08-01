require "test_helper"

class Telegram::Handlers::GameDetailHandlerTest < ActiveSupport::TestCase
  setup do
    @game = games(:one)
    @game.update_columns(date: Date.new(2026, 8, 2), recurring: false, sport: "Tennis", with_coach: false)
  end

  test "omits coach line when game has no coach" do
    text, = render_game

    assert_not_includes text, "Тренер:"
  end

  test "includes coach line when game has a coach" do
    @game.update_columns(with_coach: true)

    text, = render_game

    assert_includes text, "Тренер: С тренером"
  end

  test "includes available weather" do
    reading = Weather::GoogleForecast::Reading.new(
      temperature_c: 23.6,
      condition_type: "CLEAR",
      description: "Clear",
      precipitation_percent: 40
    )

    text, = render_game(reading: reading)

    assert_includes text, "Погода: ☀️ 24° · 40%"
  end

  test "omits unavailable weather" do
    text, = render_game(reading: nil)

    assert_not_includes text, "Погода:"
  end

  test "puts browser button last" do
    with_env("APP_HOST", "https://getcourt.co") do
      _, buttons = render_game

      assert_equal "Открыть в браузере", buttons.last.first[:text]
    end
  end

  test "renders game card in Russian" do
    text, = render_game(locale: "ru")

    assert_includes text, "*Теннис ##{@game.id}*"
    assert_includes text, "Когда: 02.08.2026"
  end

  test "renders game card in English" do
    text, = render_game(locale: "en")

    assert_includes text, "*Tennis ##{@game.id}*"
    assert_includes text, "When: 08/02/2026"
  end

  test "renders game card in Spanish" do
    text, = render_game(locale: "es")

    assert_includes text, "*Tenis ##{@game.id}*"
    assert_includes text, "Cuándo: 02/08/2026"
  end

  private
    def render_game(reading: nil, locale: "ru")
      sent = nil

      stub_singleton(Telegram::Helpers::UserLookup, :locale_for, ->(_) { locale }) do
        stub_singleton(Weather::GoogleForecast, :for_game, ->(_, timeout:) {
          assert_equal({ open: 2, read: 3 }, timeout)
          reading
        }) do
          stub_singleton(Telegram::Handlers::GameDetailHandler, :send_or_edit_with_buttons, ->(_chat_id, text, buttons, **) {
            sent = [ text, buttons ]
          }) do
            Telegram::Handlers::GameDetailHandler.show_game("123", @game.id)
          end
        end
      end

      sent
    end

    def with_env(key, value)
      old_value = ENV[key]
      ENV[key] = value
      yield
    ensure
      old_value.nil? ? ENV.delete(key) : ENV.store(key, old_value)
    end
end
