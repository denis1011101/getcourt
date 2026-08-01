require "test_helper"

class DailyTelegramNotificationsJobTest < ActiveJob::TestCase
  test "adds coach mark to game reminder" do
    text = reminder_text(with_coach: true)

    assert_includes text, "With coach"
  end

  test "omits coach mark from game reminder without coach" do
    text = reminder_text(with_coach: false)

    assert_not_includes text, "With coach"
  end

  private
    def reminder_text(with_coach:)
      game = games(:one)
      recipient = users(:one)
      game.update!(date: Date.current, recurring: false, with_coach: with_coach)
      recipient.update!(email: "reminder-#{with_coach}@example.com", telegram_chat_id: 90_006, telegram_locale: "en")
      calls = []

      stub_singleton(SendTelegramNotificationJob, :perform_later, ->(*args) { calls << args }) do
        DailyTelegramNotificationsJob.perform_now
      end

      calls.first.second
    end
end
