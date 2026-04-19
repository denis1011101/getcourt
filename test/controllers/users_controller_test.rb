require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  test "should redirect edit when not authenticated" do
    get edit_account_url
    assert_redirected_to new_session_path
  end

  test "should redirect update when not authenticated" do
    patch account_url, params: { user: { name: "New Name" } }
    assert_redirected_to new_session_path
  end

  test "authenticated user can save about_me" do
    user_email = "about_me_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)

    patch account_url, params: { user: { about_me: "I love tennis" } }

    user.reload
    assert_equal "I love tennis", user.about_me
  ensure
    user&.destroy
  end

  test "account page shows current user statistics" do
    user_email = "account_stats_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)
    user.player_statistic.update!(singles_hours: 2.5, singles_games: 1, singles_wins: 1)

    get edit_account_url

    assert_response :success
    assert_includes response.body, "Statistics"
    assert_includes response.body, "Singles: 2.5h"
  ensure
    user&.destroy
  end

  test "authenticated session is shared across locale subdomains" do
    host! "getcourt.co"
    user_email = "shared_session_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)

    host! "ru.getcourt.co"
    get edit_account_url

    assert_response :success
    assert_includes response.body, user.email
  ensure
    user&.destroy
  end

  test "sign out clears shared session across locale subdomains" do
    host! "getcourt.co"
    user_email = "shared_logout_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)

    host! "ru.getcourt.co"
    delete destroy_session_url

    host! "getcourt.co"
    get edit_account_url

    assert_redirected_to new_session_path
  ensure
    user&.destroy
  end

  test "favorites mode saves favorite courts and clears court note" do
    user_email = "favorite_courts_#{SecureRandom.hex(4)}@example.com"
    court = Court.create!(name: "Favorite Court")
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)
    user.update!(court_preferences_note: "All city courts")

    patch account_url, params: {
      user: {
        court_preferences_mode: "favorites",
        favorite_court_ids: [ court.id.to_s ],
        court_preferences_note: "Should be cleared"
      }
    }

    user.reload
    assert_equal [ court.id ], user.favorite_court_ids
    assert_nil user.court_preferences_note
  ensure
    user&.destroy
    court&.destroy
  end

  test "note mode saves court note and clears favorite courts" do
    user_email = "court_note_#{SecureRandom.hex(4)}@example.com"
    court = Court.create!(name: "Favorite Court")
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)
    user.favorite_courts << court

    patch account_url, params: {
      user: {
        court_preferences_mode: "note",
        favorite_court_ids: [ court.id.to_s ],
        court_preferences_note: "Work on all courts"
      }
    }

    user.reload
    assert_equal "Work on all courts", user.court_preferences_note
    assert_empty user.favorite_courts
  ensure
    user&.destroy
    court&.destroy
  end
end
