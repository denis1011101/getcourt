require "test_helper"

class GameReminderJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

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
    assert text.lines.first.chomp.end_with?(".")
  end

  test "sends game reminder by email when email is selected" do
    game = games(:one)
    recipient = users(:one)
    game.update!(date: Date.current, recurring: false)
    recipient.update!(email: "daily-email@example.com", notification_channel: "email", locale: "en")

    assert_enqueued_emails 1 do
      GameReminderJob.perform_now
    end
  end

  test "reminds coach today at 14 for a later game" do
    coach_text = coach_reminder_text(time: "18:00", booking_date: Date.current)

    assert_includes coach_text, "game today"
  end

  test "reminds coach a day ahead at 14 for an early game" do
    coach_text = coach_reminder_text(time: "10:00", booking_date: Date.tomorrow)

    assert_includes coach_text, "game tomorrow"
  end

  test "reminds accepted coach for a one-off game without prebooking" do
    coach = User.create!(
      email: "coach-one-off-reminder@example.com",
      coach: true,
      telegram_chat_id: 93_001,
      notification_channel: "telegram",
      telegram_locale: "en"
    )
    game = Game.create!(
      court: courts(:one),
      user: users(:two),
      coach: coach,
      with_coach: true,
      date: Date.current,
      time: "18:00"
    )
    game.update!(coach_invitation_status: "accepted")
    calls = []

    stub_singleton(SendTelegramNotificationJob, :perform_later, ->(*args) { calls << args }) do
      GameReminderJob.perform_now
    end

    assert_includes calls.find { |call| call.first == coach.telegram_chat_id }.second, "game today"
  ensure
    coach&.destroy
  end

  private
    def coach_reminder_text(time:, booking_date:)
      coach = User.create!(
        email: "coach-reminder-#{time.delete(":")}@example.com",
        coach: true,
        telegram_chat_id: 92_000 + time.to_i,
        notification_channel: "telegram",
        telegram_locale: "en"
      )
      game = Game.create!(
        court: courts(:one),
        user: users(:two),
        coach: coach,
        with_coach: true,
        recurring: true,
        date: booking_date,
        time: time
      )
      game.update!(coach_invitation_status: "accepted")
      game.coach_prebookings.create!(coach: coach, date: booking_date)
      calls = []

      stub_singleton(SendTelegramNotificationJob, :perform_later, ->(*args) { calls << args }) do
        GameReminderJob.perform_now
      end

      calls.find { |call| call.first == coach.telegram_chat_id }.second
    ensure
      coach&.destroy
    end

    def reminder_text(with_coach:, locale: "en")
      game = games(:one)
      recipient = users(:one)
      game.update!(date: Date.current, recurring: false, with_coach: with_coach)
      recipient.update!(email: "reminder-#{locale}-#{with_coach}@example.com", telegram_chat_id: 90_006, telegram_locale: locale, notification_channel: "telegram")
      calls = []

      stub_singleton(SendTelegramNotificationJob, :perform_later, ->(*args) { calls << args }) do
        GameReminderJob.perform_now
      end

      calls.first.second
    end
end
