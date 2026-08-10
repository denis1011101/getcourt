require "test_helper"

class GameRequestNotificationTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "participation result uses email preference" do
    user = User.create!(email: "participation-result@example.com", notification_channel: "email", locale: "en")

    assert_enqueued_emails 1 do
      GameRequestNotification.participation(user: user, game: games(:one), approved: true)
    end
  ensure
    user&.destroy
  end

  test "prebooking result uses telegram preference" do
    user = User.create!(email: "prebooking-result@example.com", telegram_chat_id: 98_765, telegram_locale: "en", notification_channel: "telegram")
    calls = []

    stub_singleton(SendTelegramNotificationJob, :perform_later, ->(*args, **kwargs) { calls << [ args, kwargs ] }) do
      GameRequestNotification.prebooking(user: user, game: games(:one), dates: Date.current + 2.days, approved: false)
    end

    assert_equal user.telegram_chat_id, calls.first.first.first
    assert_includes calls.first.first.second, "was rejected"
  ensure
    user&.destroy
  end
end
