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

  test "show_profile includes favorite courts and court note" do
    user = User.create!(
      email: "profile_handler_courts_#{SecureRandom.hex(4)}@example.com",
      telegram_chat_id: "ph_2",
      coach: true,
      court_preferences_note: "All courts in the city"
    )
    court = Court.create!(name: "Center Court")
    user.favorite_courts << court
    sent_text = nil

    stub_singleton(Telegram::Helpers::UserLookup, :find_user, ->(_) { user }) do
      stub_singleton(Telegram::Handlers::ProfileHandler, :send_or_edit_with_buttons, ->(_chat_id, text, _buttons, **_kw) { sent_text = text }) do
        Telegram::Handlers::ProfileHandler.show_profile("ph_2")
      end
    end

    assert_includes sent_text, "Center Court"
    assert_includes sent_text, "All courts in the city"
  ensure
    user&.destroy
    court&.destroy
  end

  private

  def stub_singleton(target, method_name, replacement)
    singleton = target.singleton_class
    had_method = singleton.method_defined?(method_name) || singleton.private_method_defined?(method_name)
    original = singleton.instance_method(method_name) if had_method
    callable = replacement.respond_to?(:call) ? replacement : ->(*) { replacement }

    singleton.define_method(method_name) do |*args, **kwargs, &block|
      callable.call(*args, **kwargs, &block)
    end

    yield
  ensure
    if had_method
      singleton.define_method(method_name, original)
    else
      singleton.remove_method(method_name)
    end
  end
end
