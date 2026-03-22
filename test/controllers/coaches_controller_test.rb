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

  test "renders pages_nav with links to other pages but not to itself" do
    get coaches_url

    assert_select "a[href='#{contacts_path}']", "Contact"
    assert_select "a[href='#{ntrp_level_guide_path}']", "NTRP Guide"
    assert_select "a[href='#{tennis_formats_and_rules_path}']", "Formats & Rules"
    assert_select "a[href='#{partnership_path}']", "Partnership"
    assert_select "a[href='#{mission_path}']", "Mission"
    assert_select "div.mt-6 a[href='#{coaches_path}']", count: 0
  end
end
