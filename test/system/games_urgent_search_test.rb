require "application_system_test_case"

class GamesUrgentSearchTest < ApplicationSystemTestCase
  test "owner toggles urgent search from game page" do
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
    assert_button "Announce urgent search"
    click_on "Announce urgent search"

    assert_current_path game_path(game)
    assert game.reload.urgent_player_search?
    assert_button "Cancel urgent search"

    click_on "Cancel urgent search"
    assert_current_path game_path(game)
    assert_not game.reload.urgent_player_search?
    assert_button "Announce urgent search"
  end
end
