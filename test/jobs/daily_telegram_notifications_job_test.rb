require "test_helper"

class DailyTelegramNotificationsJobTest < ActiveJob::TestCase
  test "adds coach mark to game reminder" do
    text = reminder_text(with_coach: true)

    assert_match(/\A.* — With coach\n/, text)
    assert_includes text, "Reminder: you have a game today"
  end


  test "localizes game reminder in Russian" do
    text = reminder_text(with_coach: true, locale: "ru")

    assert_includes text, "Напоминание: у вас игра сегодня"
    assert_includes text, Date.current.strftime("%d.%m.%Y")
    assert_includes text, " — С тренером\n"
  end

  test "localizes game reminder in Spanish" do
    text = reminder_text(with_coach: true, locale: "es")

    assert_includes text, "Recordatorio: tienes un partido hoy"
    assert_includes text, Date.current.strftime("%d/%m/%Y")
    assert_includes text, " — Con entrenador\n"
  end

  test "omits coach mark from game reminder without coach" do
    text = reminder_text(with_coach: false)

    assert_not_includes text.lines.first, " — With coach"
  end

  private
    def reminder_text(with_coach:, locale: "en")
      game = games(:one)
      recipient = users(:one)
      game.update!(date: Date.current, recurring: false, with_coach: with_coach)
      recipient.update!(email: "reminder-#{locale}-#{with_coach}@example.com", telegram_chat_id: 90_006, telegram_locale: locale)
      calls = []

      stub_singleton(SendTelegramNotificationJob, :perform_later, ->(*args) { calls << args }) do
        DailyTelegramNotificationsJob.perform_now
      end

      calls.first.second
    end
end
