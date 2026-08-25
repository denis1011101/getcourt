require "test_helper"

class Games::ShareCardRendererTest < ActiveSupport::TestCase
  test "card markup repeats the badges, the comment and the free spots of the games list" do
    game = games(:feed_upcoming)
    # Корт из фикстуры разрешает не любое покрытие, а карточке важны только атрибуты игры.
    game.assign_attributes(
      kind: "training",
      sport: "tennis",
      surface: "hard",
      environment: "outdoor",
      skill_level: "intermediate",
      with_coach: true,
      recurring: true,
      urgent_player_search: true,
      comment: "Ракетки и мячи свои"
    )

    svg = markup_for(game)

    assert_includes svg, "Feed Court"
    assert_includes svg, "Tennis"
    assert_includes svg, "Intermediate"
    assert_includes svg, "Hard"
    assert_includes svg, "Outdoor"
    assert_includes svg, I18n.t("games.badges.training", locale: :en)
    assert_includes svg, I18n.t("games.badges.coach", locale: :en)
    assert_includes svg, I18n.t("games.badges.weekly", locale: :en)
    assert_includes svg, I18n.t("games.badges.player_search", locale: :en)
    assert_includes svg, "Ракетки и мячи свои"
    assert_includes svg, I18n.t("games.card.spots_left", count: 4, locale: :en)
  end

  test "weather badge is skipped for indoor games" do
    game = games(:feed_upcoming)
    game.assign_attributes(environment: "indoor")

    called = false
    stub_singleton(Weather::GoogleForecast, :for_game, ->(*) { called = true; nil }) do
      Games::ShareCardRenderer.send(:svg_markup, game, locale: :en)
    end

    assert_not called, "indoor game must not go to the forecast"
  end

  test "renders a png" do
    data = markup_free_render(games(:feed_upcoming))

    assert_equal "\x89PNG\r\n\x1A\n".b, data[0, 8].b
  end

  private

  def markup_for(game)
    stub_singleton(Weather::GoogleForecast, :for_game, nil) do
      Games::ShareCardRenderer.send(:svg_markup, game, locale: :en)
    end
  end

  def markup_free_render(game)
    stub_singleton(Weather::GoogleForecast, :for_game, nil) do
      Games::ShareCardRenderer.render_data(game, locale: :en)
    end
  end
end
