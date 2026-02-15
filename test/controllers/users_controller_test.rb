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
end
