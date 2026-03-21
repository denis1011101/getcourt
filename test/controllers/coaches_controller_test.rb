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
    assert_select "h1", "Coaches"
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
end
