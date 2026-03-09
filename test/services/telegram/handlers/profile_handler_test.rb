require "test_helper"

class Telegram::Handlers::ProfileHandlerTest < ActiveSupport::TestCase
  test "show_profile includes about_me in rendered text" do
    user = User.create!(
      email: "profile_handler_#{SecureRandom.hex(4)}@example.com",
      about_me: "Weekend tennis player",
      telegram_chat_id: "ph_1"
    )
    sent_text = nil

    stub_singleton(Telegram::Helpers::UserLookup, :find_user, ->(_) { user }) do
      stub_singleton(Telegram::Handlers::ProfileHandler, :send_or_edit_with_buttons, ->(_chat_id, text, _buttons, **_kw) { sent_text = text }) do
        Telegram::Handlers::ProfileHandler.show_profile("ph_1")
      end
    end

    assert_includes sent_text, "Weekend tennis player"
  ensure
    user&.destroy
  end
end
