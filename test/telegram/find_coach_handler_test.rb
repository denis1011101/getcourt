require "test_helper"

class Telegram::Handlers::FindCoachHandlerTest < ActiveSupport::TestCase
  test "list_page prioritizes coaches with overlapping favorite courts" do
    user = User.create!(email: "find_coach_user_#{SecureRandom.hex(4)}@example.com", telegram_chat_id: "fc_user", city_name: "Moscow")
    court = Court.create!(name: "Favorite Court")
    user.favorite_courts << court

    prioritized = User.create!(email: "coach_overlap_#{SecureRandom.hex(4)}@example.com", name: "Overlap Coach", coach: true, city_name: "London")
    prioritized.favorite_courts << court
    fallback = User.create!(email: "coach_plain_#{SecureRandom.hex(4)}@example.com", name: "Plain Coach", coach: true, city_name: "Moscow")

    sent_buttons = nil

    stub_singleton(Telegram::Helpers::UserLookup, :locale_for, ->(_) { "en" }) do
      stub_singleton(Telegram::Helpers::UserLookup, :find_user, ->(_) { user }) do
        stub_singleton(Telegram::Handlers::FindCoachHandler, :send_or_edit_with_buttons, ->(_chat_id, _text, buttons, **_kw) { sent_buttons = buttons }) do
          Telegram::Handlers::FindCoachHandler.list_page("fc_user")
        end
      end
    end

    coach_buttons = sent_buttons.select { |row| row.first[:callback_data].start_with?("coach:show:") }
    assert_includes coach_buttons.first.first[:text], "Overlap Coach"
  ensure
    user&.destroy
    prioritized&.destroy
    fallback&.destroy
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
