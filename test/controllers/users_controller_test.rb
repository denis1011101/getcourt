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
end
