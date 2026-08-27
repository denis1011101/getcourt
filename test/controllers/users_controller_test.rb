require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  test "should redirect edit when not authenticated" do
    get edit_account_url
    assert_redirected_to new_session_path
  end

  test "should redirect account subpages when not authenticated" do
    [
      profile_account_url,
      notifications_account_url,
      security_account_url,
      courts_account_url
    ].each do |path|
      get path
      assert_redirected_to new_session_path
    end
  end

  test "should redirect update when not authenticated" do
    patch account_url, params: { user: { name: "New Name" } }
    assert_redirected_to new_session_path
  end

  test "authenticated user can save about_me" do
    user_email = "about_me_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)

    patch account_url, params: { section: "profile", user: { about_me: "I love tennis" } }

    user.reload
    assert_equal "I love tennis", user.about_me
    assert_redirected_to profile_account_path
  ensure
    user&.destroy
  end

  test "authenticated user can view account subpages" do
    user_email = "account_subpages_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)

    [
      [ profile_account_url, "Profile" ],
      [ notifications_account_url, "Telegram & notifications" ],
      [ security_account_url, "Security" ],
      [ courts_account_url, "Court preferences" ]
    ].each do |path, heading|
      get path
      assert_response :success
      assert_includes response.body, heading
    end
  ensure
    user&.destroy
  end

  test "account page shows a statistics teaser linking to the full stats page" do
    user_email = "account_stats_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)
    user.player_statistic.update!(singles_hours: 2.5, singles_games: 1, singles_wins: 1)

    get edit_account_url

    assert_response :success
    assert_includes response.body, "Statistics"
    assert_includes response.body, "2.5h"
    assert_includes response.body, "View full statistics"
    # Teaser link opens the on-page stats modal (CSS :target), not a bare page.
    assert_select "a[href=?]", "#player-stats-#{user.id}"
    assert_select "##{"player-stats-#{user.id}"}.ps-modal"
  ensure
    user&.destroy
  end

  test "account courts page sorts local favorite court options first by name" do
    user_email = "court_sort_#{SecureRandom.hex(4)}@example.com"
    local_a = Court.create!(name: "Alpha Local", city_name: "Testville", moderation_status: "approved")
    local_b = Court.create!(name: "Zulu Local", city_name: "Testville", moderation_status: "approved")
    other = Court.create!(name: "Alpha Away", city_name: "Awaytown", moderation_status: "approved")

    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)
    user.update!(city_name: "Testville")

    get courts_account_url

    assert_response :success
    assert_select "form[action='#{account_path}']"

    body = response.body
    alpha_local = body.index("Alpha Local")
    zulu_local = body.index("Zulu Local")
    alpha_away = body.index("Alpha Away")

    assert alpha_local, "Alpha Local not found in account page"
    assert zulu_local, "Zulu Local not found in account page"
    assert alpha_away, "Alpha Away not found in account page"
    assert_operator alpha_local, :<, zulu_local
    assert_operator zulu_local, :<, alpha_away
  ensure
    user&.destroy
    local_a&.destroy
    local_b&.destroy
    other&.destroy
  end

  test "authenticated session is shared across locale subdomains" do
    host! "getcourt.co"
    user_email = "shared_session_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)

    host! "ru.getcourt.co"
    get profile_account_url

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
      section: "courts",
      user: {
        court_preferences_mode: "favorites",
        favorite_court_ids: [ court.id.to_s ],
        court_preferences_note: "Should be cleared"
      }
    }

    user.reload
    assert_equal [ court.id ], user.favorite_court_ids
    assert_nil user.court_preferences_note
    assert_redirected_to courts_account_path
  ensure
    user&.destroy
    court&.destroy
  end

  test "profile update does not clear favorite courts" do
    user_email = "profile_keeps_courts_#{SecureRandom.hex(4)}@example.com"
    court = Court.create!(name: "Kept Favorite Court")
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)
    user.favorite_courts << court

    patch account_url, params: {
      section: "profile",
      user: {
        name: "Profile Update",
        email: user.email
      }
    }

    user.reload
    assert_equal "Profile Update", user.name
    assert_equal [ court.id ], user.favorite_court_ids
    assert_redirected_to profile_account_path
  ensure
    user&.destroy
    court&.destroy
  end

  test "notifications update redirects back to notifications" do
    user_email = "notifications_redirect_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)

    patch account_url, params: {
      section: "notifications",
      user: { notify_nearby: "1", notification_channel: "email" }
    }

    assert_redirected_to notifications_account_path
    user.reload
    assert_equal true, user.notify_nearby
    assert_equal "email", user.notification_channel
  ensure
    user&.destroy
  end

  test "notifications page shows nearby notification channel selector" do
    user_email = "notifications_channel_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }

    get notifications_account_url

    assert_response :success
    assert_select "select[name='user[notification_channel]']" do
      assert_select "option[value='email']"
      assert_select "option[value='telegram']"
    end
    assert_not_includes response.body, I18n.t("users.notifications.telegram_required")

    user = User.find_by!(email: user_email)
    user.update!(notification_channel: "telegram")
    get notifications_account_url

    assert_includes response.body, I18n.t("users.notifications.telegram_required")
  ensure
    User.find_by(email: user_email)&.destroy if defined?(user_email)
  end

  test "security update redirects back to security" do
    user_email = "security_redirect_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)

    patch account_url, params: {
      section: "security",
      user: { require_verification: "1", preferred_login_via: "email" }
    }

    assert_redirected_to security_account_path
    assert_equal true, user.reload.require_verification
    assert_equal "email", user.preferred_login_via
  ensure
    user&.destroy
  end

  test "invalid profile update renders profile with unprocessable entity" do
    user_email = "invalid_profile_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)

    patch account_url, params: {
      section: "profile",
      user: { email: "" }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "Profile"
  ensure
    user&.destroy
  end

  test "regenerate token redirects to notifications" do
    user_email = "regenerate_redirect_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)

    post regenerate_token_account_url

    assert_redirected_to notifications_account_path
  ensure
    user&.destroy
  end

  test "clear city redirects to profile" do
    user_email = "clear_city_redirect_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)
    user.update!(city_name: "Kurgan")

    post clear_city_account_url

    assert_redirected_to profile_account_path
    assert_nil user.reload.city_name
  ensure
    user&.destroy
  end

  test "account games shows past matches when user has no live games" do
    user_email = "past_matches_only_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)
    match = Match.create!(
      user: user,
      mode: "singles",
      outcome: "win",
      score: "6-4 6-3",
      played_at: 3.days.ago
    )

    get games_account_url

    assert_response :success
    assert_includes response.body, "Past matches"
    assert_includes response.body, "6-4 6-3"
  ensure
    match&.destroy
    user&.destroy
  end

  test "account games shows past matches alongside live games" do
    user_email = "past_and_live_#{SecureRandom.hex(4)}@example.com"
    court = Court.create!(name: "Match History Court")
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)
    game = Game.create!(user: user, court: court, date: 5.days.from_now.to_date, time: "10:00")
    old_match = Match.create!(
      user: user,
      mode: "singles",
      outcome: "loss",
      score: "2-6 3-6",
      played_at: 30.days.ago
    )
    get games_account_url

    assert_response :success
    assert_includes response.body, "Match History Court"
    assert_includes response.body, "Past matches"
    assert_includes response.body, "2-6 3-6"
  ensure
    old_match&.destroy
    game&.destroy
    court&.destroy
    user&.destroy
  end

  test "account games deduplicates matches linked to live games" do
    user_email = "dedup_match_#{SecureRandom.hex(4)}@example.com"
    court = Court.create!(name: "Dedup Court")
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)
    game = Game.create!(user: user, court: court, date: 2.days.from_now.to_date, time: "12:00")
    linked_match = Match.create!(
      user: user,
      game: game,
      mode: "singles",
      outcome: "win",
      score: "UNIQUE-SCORE-A",
      played_at: 1.day.ago
    )
    orphan_match = Match.create!(
      user: user,
      mode: "singles",
      outcome: "loss",
      score: "UNIQUE-SCORE-B",
      played_at: 7.days.ago
    )

    get games_account_url

    assert_response :success
    refute_includes response.body, "UNIQUE-SCORE-A"
    assert_includes response.body, "UNIQUE-SCORE-B"
  ensure
    linked_match&.destroy
    orphan_match&.destroy
    game&.destroy
    court&.destroy
    user&.destroy
  end

  test "account games hides past matches section when none exist" do
    user_email = "no_history_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)

    get games_account_url

    assert_response :success
    refute_includes response.body, "Past matches"
  ensure
    user&.destroy
  end

  test "note mode saves court note and clears favorite courts" do
    user_email = "court_note_#{SecureRandom.hex(4)}@example.com"
    court = Court.create!(name: "Favorite Court")
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)
    user.favorite_courts << court

    patch account_url, params: {
      section: "courts",
      user: {
        court_preferences_mode: "note",
        favorite_court_ids: [ court.id.to_s ],
        court_preferences_note: "Work on all courts"
      }
    }

    user.reload
    assert_equal "Work on all courts", user.court_preferences_note
    assert_empty user.favorite_courts
    assert_redirected_to courts_account_path
  ensure
    user&.destroy
    court&.destroy
  end
  test "account page links to the training blocks library for a coach" do
    coach = User.create!(email: "coach-library-#{SecureRandom.hex(4)}@example.com", coach: true)
    post session_url, params: { email: coach.email }

    get edit_account_url

    assert_response :success
    assert_includes response.body, training_blocks_path
    assert_includes response.body, "Training constructor"
  ensure
    coach&.destroy
  end

  test "account page hides the training blocks library from a player without blocks" do
    user_email = "player_library_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)

    get edit_account_url

    assert_response :success
    assert_not_includes response.body, training_blocks_path
  ensure
    user&.destroy
  end

  test "coach sees confirmed future dates in account games" do
    coach = User.create!(email: "coach-schedule@example.com", coach: true)
    game = Game.create!(
      court: courts(:one),
      user: users(:one),
      coach: coach,
      with_coach: true,
      recurring: true,
      date: Date.current
    )
    game.update!(coach_invitation_status: "accepted")
    game.coach_prebookings.create!(coach: coach, date: game.next_date)
    post session_url, params: { email: coach.email }

    get games_account_url

    assert_response :success
    assert_includes response.body, "Coaching schedule"
    assert_includes response.body, game.court.name
  ensure
    coach&.destroy
  end

  test "coach schedule includes accepted one-off games without a prebooking" do
    coach = User.create!(email: "coach-one-off-schedule@example.com", coach: true)
    game = Game.create!(
      court: courts(:one),
      user: users(:one),
      coach: coach,
      with_coach: true,
      date: Date.tomorrow,
      time: "17:00"
    )
    game.update!(coach_invitation_status: "accepted")
    post session_url, params: { email: coach.email }

    get games_account_url

    assert_response :success
    assert_includes response.body, game.court.name
    assert_includes response.body, I18n.l(game.date, format: :long)
  ensure
    coach&.destroy
  end
  test "newcomer sees the checklist on the homepage and can close it for good" do
    newcomer = User.create!(email: "checklist-newcomer@example.com")
    post session_url, params: { email: newcomer.email }

    get root_url
    assert_response :success
    assert_includes response.body, I18n.t("users.onboarding.title")

    post dismiss_onboarding_account_url

    get root_url
    assert_response :success
    assert_not_includes response.body, I18n.t("users.onboarding.title")
    assert newcomer.reload.onboarding_dismissed?
  ensure
    newcomer&.destroy
  end

  test "account games lists trainings where the user is the second coach" do
    coach_email = "second_coach_schedule_#{SecureRandom.hex(4)}@example.com"
    court = Court.create!(name: "Second Coach Court")
    first = User.create!(email: "schedule_first_coach_#{SecureRandom.hex(4)}@example.com", coach: true)
    post session_url, params: { email: coach_email }
    coach = User.find_by!(email: coach_email)
    coach.update!(coach: true)
    game = Game.create!(
      court: court,
      user: users(:one),
      date: Date.current + 2.days,
      time: "19:00",
      kind: "training",
      with_coach: true,
      coach: first,
      second_coach: coach
    )
    game.update!(second_coach_invitation_status: "accepted")

    get games_account_url

    assert_response :success
    assert_not_includes response.body, I18n.t("users.games.coach_schedule_empty")
    assert_includes response.body, court.name
  ensure
    game&.destroy
    first&.destroy
    coach&.destroy
    court&.destroy
  end
end
