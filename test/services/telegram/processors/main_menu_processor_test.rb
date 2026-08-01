require "test_helper"

class Telegram::Processors::MainMenuProcessorTest < ActiveSupport::TestCase
  test "confirms successful account registration before showing the site link" do
    user = users(:one)
    user.update!(email: "telegram-register@example.com", telegram_registration_token: "registration-token")
    message = {
      "chat" => { "id" => 12_345 },
      "from" => { "id" => 12_345, "username" => "registered_user" },
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
    assert_equal [ "12345", "Telegram connected to your GetCourt account." ], args
    assert_nil kwargs[:parse_mode]
    assert_equal [ "12345" ], menu_chat_ids
    assert_equal 12_345, user.reload.telegram_chat_id
  end
end
