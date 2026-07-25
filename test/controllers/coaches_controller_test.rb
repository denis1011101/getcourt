require "test_helper"

class CoachesControllerTest < ActionDispatch::IntegrationTest
  test "should get index and list only coaches" do
    coach = User.create!(
      email: "coach@example.com",
      name: "Coach One",
      coach: true,
      preferred_sports: [ "Tennis" ],
      city_name: "London"
    )
    User.create!(
      email: "player@example.com",
      name: "Regular Player",
      coach: false
    )

    get coaches_url

    assert_response :success
    assert_select "h1", "Find a Tennis Coach"
    assert_match coach.name, @response.body
    assert_no_match "Regular Player", @response.body
  end

  test "shows telegram link when telegram_username present" do
    User.create!(
      email: "tgcoach@example.com",
      name: "TG Coach",
      coach: true,
      telegram_username: "mycoach"
    )

    get coaches_url

    assert_select "a[href='https://t.me/mycoach']", "mycoach"
  end

  test "does not show telegram link when telegram_username absent" do
    User.create!(
      email: "notgcoach@example.com",
      name: "No TG Coach",
      coach: true,
      telegram_username: nil
    )

    get coaches_url

    assert_select "h2", text: /No TG Coach/
    assert_select "h2 a[href^='https://t.me/']", count: 0
  end

  test "shows favorite courts when coach selected them" do
    coach = User.create!(
      email: "courtcoach@example.com",
      name: "Court Coach",
      coach: true
    )
    court = Court.create!(name: "Center Court")
    coach.favorite_courts << court

    get coaches_url

    assert_select "a[href='#{court_path(court)}']", text: "Center Court"
  ensure
    coach&.destroy
    court&.destroy
  end

  test "shows court note instead of favorite courts when note present" do
    coach = User.create!(
      email: "notecoach@example.com",
      name: "Note Coach",
      coach: true,
      court_preferences_note: "All courts in the city"
    )
    court = Court.create!(name: "Center Court")
    coach.favorite_courts << court

    get coaches_url

    assert_match "All courts in the city", @response.body
  ensure
    coach&.destroy
    court&.destroy
  end

  test "sets seo title and meta description" do
    get coaches_url

    assert_select "title", text: /Find a Tennis Coach/
    assert_select "meta[name='description'][content*='tennis coach']", count: 1
  end

  test "empty state shows helpful content instead of just a blank message" do
    get coaches_url

    assert_select "h2", text: /How to choose a tennis coach/i
    assert_select "h2", text: /For coaches/i
    assert_select "a[href='#{new_session_path}']"
  end

  # ---- location filters ---------------------------------------------------

  test "index filters coaches by city" do
    local = User.create!(email: "kazan_coach@example.com", name: "Kazan Coach", coach: true, city_name: "Kazan")
    remote = User.create!(email: "moscow_coach@example.com", name: "Moscow Coach", coach: true, city_name: "Moscow")

    get coaches_url, params: { city: "Kazan" }

    assert_response :success
    assert_includes @controller.instance_variable_get(:@coaches), local
    assert_not_includes @controller.instance_variable_get(:@coaches), remote
  ensure
    local&.destroy
    remote&.destroy
  end

  test "index filters coaches by country" do
    city_ids = []
    city_ids << City.create!(name: "Kitzbuhel", country_code: "AT", population: 8_000).id
    city_ids << City.create!(name: "Yekaterinburg", country_code: "RU", population: 1_500_000).id
    austrian = User.create!(email: "at_coach@example.com", name: "Austrian Coach", coach: true, city_name: "Kitzbuhel")
    russian = User.create!(email: "ru_coach@example.com", name: "Russian Coach", coach: true, city_name: "Yekaterinburg")

    get coaches_url, params: { country: "AT" }

    assert_response :success
    coaches = @controller.instance_variable_get(:@coaches)
    assert_includes coaches, austrian
    assert_not_includes coaches, russian
    assert_match "Austria", @response.body
  ensure
    austrian&.destroy
    russian&.destroy
    City.where(id: city_ids).delete_all
  end

  test "coaches from your city come first when no location filter is applied" do
    user_email = "coach_seeker_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }
    User.find_by!(email: user_email).update_column(:city_name, "Yekaterinburg")

    remote = User.create!(email: "aaa_remote_coach@example.com", name: "Aaa Remote Coach", coach: true, city_name: "Moscow")
    local = User.create!(email: "zzz_local_coach@example.com", name: "Zzz Local Coach", coach: true, city_name: "Ekaterinburg")

    get coaches_url

    coaches = @controller.instance_variable_get(:@coaches)
    assert coaches.index(local) < coaches.index(remote),
           "Coach from the user's city should be listed before coaches from other cities"
  ensure
    local&.destroy
    remote&.destroy
    User.find_by(email: user_email)&.destroy
  end

  test "renders pages_nav with links to other pages but not to itself" do
    get coaches_url

    assert_select "a[href='#{contacts_path}']", I18n.t("layout.nav.contacts")
    assert_select "a[href='#{ntrp_level_guide_path}']", "NTRP Guide"
    assert_select "a[href='#{tennis_formats_and_rules_path}']", "Formats & Rules"
    assert_select "a[href='#{partnership_path}']", "Partnership"
    assert_select "a[href='#{mission_path}']", "Mission"
    assert_select "div.mt-6 a[href='#{coaches_path}']", count: 0
  end
end
