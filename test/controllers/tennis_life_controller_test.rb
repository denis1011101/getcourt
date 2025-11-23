require "test_helper"

class TennisLifeControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get tennis_life_index_url
    assert_response :success
  end
end
