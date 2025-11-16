require "test_helper"

class GeocodingControllerTest < ActionDispatch::IntegrationTest
  test "should get status" do
    get geocoding_status_url
    assert_response :success
  end

  test "should get reset" do
    get geocoding_reset_url
    assert_response :success
  end
end
