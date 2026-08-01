require "test_helper"

class Telegram::UserServiceTest < ActiveSupport::TestCase
  test "stores a supported Telegram language for a new user" do
    user, created = Telegram::UserService.find_or_create_for_chat(
      { "id" => 76_501, "username" => "spanish_user", "first_name" => "Nuevo" },
      language_code: "es-ES"
    )

    assert created
    assert_equal "es", user.telegram_locale
  end

  test "does not overwrite an existing Telegram locale" do
    user = users(:one)
    user.update!(email: "existing-user-service@example.com", telegram_chat_id: 76_502, telegram_locale: "en")

    Telegram::UserService.find_or_create_for_chat({ "id" => 76_502 }, language_code: "es")

    assert_equal "en", user.reload.telegram_locale
  end

  test "stores Telegram language for an existing user without a locale" do
    user = users(:one)
    user.update!(email: "unset-user-service@example.com", telegram_chat_id: 76_503, telegram_locale: nil)

    Telegram::UserService.find_or_create_for_chat({ "id" => 76_503 }, language_code: "es-ES")

    assert_equal "es", user.reload.telegram_locale
  end
end
