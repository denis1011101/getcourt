require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "requires email even when telegram chat id is present" do
    user = User.new(telegram_chat_id: "12345", name: "Telegram User")

    assert_not user.valid?
    assert_includes user.errors[:email], "can't be blank"
  end

  test "accepts generated telegram account email" do
    user = User.new(
      email: "tg-#{SecureRandom.hex(8)}@telegram.getcourt",
      telegram_chat_id: "54321",
      telegram_generated_email: true,
      name: "Telegram User"
    )

    assert user.valid?
  end

  test "all web locales format default dates and short times" do
    User::WEB_LOCALES.each do |locale|
      assert_predicate I18n.l(Date.current, locale: locale), :present?
      assert_predicate I18n.l(Time.current, format: :short, locale: locale), :present?
    end
  end
end
