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

  test "telegram locale is optional without an implicit default" do
    column = User.columns_hash.fetch("telegram_locale")

    assert column.null
    assert_nil column.default
    assert_nil User.new.telegram_locale
  end

  test "defaults notification channel to telegram when telegram is connected" do
    user = User.new(email: "telegram-channel@example.com", telegram_chat_id: 12_345)

    assert user.valid?
    assert_equal "telegram", user.notification_channel
  end

  test "defaults notification channel to email without telegram" do
    user = User.new(email: "email-channel@example.com")

    assert user.valid?
    assert_equal "email", user.notification_channel
  end

  test "identifiable keeps players who only have a telegram handle" do
    from_bot = User.create!(email: "pickable-bot@example.com", telegram_username: "pickable_nick")
    nameless = User.create!(email: "not-pickable@example.com")

    identifiable = User.identifiable

    assert_includes identifiable, from_bot
    assert_not_includes identifiable, nameless
  end

  test "by_display_label sorts by what the picker shows" do
    zoe = User.create!(email: "zoe-sorted@example.com", name: "Zoe")
    anna = User.create!(email: "anna-sorted@example.com", name: "anna")

    ordered = User.where(id: [ zoe.id, anna.id ]).by_display_label

    assert_equal [ anna, zoe ], ordered.to_a
  end
end
