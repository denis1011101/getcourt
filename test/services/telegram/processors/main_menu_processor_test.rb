require "test_helper"

class Telegram::Processors::MainMenuProcessorTest < ActiveSupport::TestCase
  test "confirms successful account registration before showing the site link" do
    user = users(:one)
    user.update!(email: "telegram-register@example.com", telegram_registration_token: "registration-token", telegram_locale: nil)
    message = {
      "chat" => { "id" => 12_345 },
      "from" => { "id" => 12_345, "username" => "registered_user", "language_code" => "es-ES" },
      "text" => "/register registration-token"
    }
    notifications = []
    menu_chat_ids = []

    stub_singleton(Telegram::Api, :send_simple, ->(*args, **kwargs) { notifications << [ args, kwargs ] }) do
      stub_singleton(Telegram::Handlers::MenuHandler, :menu, ->(chat_id) { menu_chat_ids << chat_id }) do
        Telegram::Processors::MainMenuProcessor.handle_message(message)
      end
    end

    assert_equal 1, notifications.size
    args, kwargs = notifications.first
    assert_equal [ "12345", "Telegram se ha conectado a tu cuenta de GetCourt." ], args
    assert_nil kwargs[:parse_mode]
    assert_equal [ "12345" ], menu_chat_ids
    assert_equal 12_345, user.reload.telegram_chat_id
    assert_equal "es", user.telegram_locale
  end

  test "start stores telegram language for a new user" do
    chat_id = 98_765
    message = {
      "chat" => { "id" => chat_id },
      "from" => { "id" => chat_id, "first_name" => "Nuevo", "language_code" => "es-ES" },
      "text" => "/start"
    }

    stub_singleton(Telegram::Handlers::MenuHandler, :menu, ->(*) { }) do
      Telegram::Processors::MainMenuProcessor.handle_message(message)
    end

    assert_equal "es", User.find_by!(telegram_chat_id: chat_id).telegram_locale
  end

  test "start does not overwrite an existing telegram locale" do
    user = users(:one)
    user.update!(email: "existing-start-locale@example.com", telegram_chat_id: 98_766, telegram_locale: "en")
    message = {
      "chat" => { "id" => user.telegram_chat_id },
      "from" => { "id" => user.telegram_chat_id, "language_code" => "es" },
      "text" => "/start"
    }

    stub_singleton(Telegram::Handlers::MenuHandler, :menu, ->(*) { }) do
      Telegram::Processors::MainMenuProcessor.handle_message(message)
    end

    assert_equal "en", user.reload.telegram_locale
  end

  test "start stores telegram language for an existing user without a locale" do
    user = users(:one)
    user.update!(email: "unset-start-locale@example.com", telegram_chat_id: 98_767, telegram_locale: nil)
    message = {
      "chat" => { "id" => user.telegram_chat_id },
      "from" => { "id" => user.telegram_chat_id, "language_code" => "es-ES" },
      "text" => "/start"
    }

    stub_singleton(Telegram::Handlers::MenuHandler, :menu, ->(*) { }) do
      Telegram::Processors::MainMenuProcessor.handle_message(message)
    end

    assert_equal "es", user.reload.telegram_locale
  end
end
