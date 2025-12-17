require "test_helper"

class PrebookingsControllerTest < ActionDispatch::IntegrationTest
  test "should get claim" do
    get prebookings_claim_url
    assert_response :success
  end

  test "should get unclaim" do
    get prebookings_unclaim_url
    assert_response :success
  end
end
