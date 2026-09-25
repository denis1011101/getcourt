require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  # Табло открыто всем, как и страница игры: гостя не отклоняем.
  test "a guest connects without a user" do
    connect

    assert_nil connection.current_user
  end

  # Вход живёт в сессии, а не в отдельной куке — её кабель и читает.
  test "a signed-in user is recognised from the session cookie" do
    user = User.create!(email: "cable-user@example.com")
    # Хеш в куке надо обернуть в value: голый хеш jar принимает за опции.
    cookies.encrypted[Rails.application.config.session_options[:key]] = { value: { "user_id" => user.id } }

    connect

    assert_equal user, connection.current_user
  end
end
