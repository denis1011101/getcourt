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
end
