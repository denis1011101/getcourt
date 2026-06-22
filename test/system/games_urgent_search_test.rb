require "application_system_test_case"

class GamesUrgentSearchTest < ApplicationSystemTestCase
  test "owner toggles players search from game page" do
    owner = User.create!(email: "system_owner_urgent@example.com")
    game = Game.create!(
      court: courts(:one),
      user: owner,
      date: Date.current + 1.day,
      time: "20:00"
    )

    visit new_session_path
    fill_in "Email", with: owner.email
    click_on "Enter"

    visit game_path(game)
    assert_button "Announce players search"
    click_on "Announce players search"

    assert_current_path game_path(game)
    assert game.reload.urgent_player_search?
    assert_button "Cancel players search"

    click_on "Cancel players search"
    assert_current_path game_path(game)
    assert_not game.reload.urgent_player_search?
    assert_button "Announce players search"
  end
end
