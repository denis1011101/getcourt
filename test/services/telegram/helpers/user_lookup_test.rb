require "test_helper"

class Telegram::Helpers::UserLookupTest < ActiveSupport::TestCase
  test "prefers the telegram handle in telegram" do
    assert_equal "@player", Telegram::Helpers::UserLookup.display_name(user, channel: :telegram)
  end

  test "prefers the name and the address in email" do
    assert_equal "Иван Петров", Telegram::Helpers::UserLookup.display_name(user, channel: :email)
    assert_equal "lookup@example.com", Telegram::Helpers::UserLookup.display_name(user(name: nil), channel: :email)
    assert_equal "@player", Telegram::Helpers::UserLookup.display_name(user(name: nil, email: nil), channel: :email)
  end

  test "skips the address the bot made up at registration" do
    generated = user(name: nil, telegram_username: nil, telegram_generated_email: true)

    assert_equal "Гость", Telegram::Helpers::UserLookup.display_name(generated, fallback: "Гость", channel: :email)
  end

  private
    def user(name: "Иван Петров", telegram_username: "player", email: "lookup@example.com", telegram_generated_email: false)
      User.new(
        name: name,
        email: email,
        telegram_username: telegram_username,
        telegram_generated_email: telegram_generated_email
      )
    end
end
