require "test_helper"

class GameReminderJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  test "adds coach mark to training reminder" do
    text = reminder_text(with_coach: true)

    assert_match(/\A.* — With coach\n/, text)
    assert_includes text, "Reminder: you have a training today"
  end


  test "localizes game reminder in Russian" do
    text = reminder_text(with_coach: true, locale: "ru")

    assert_includes text, "Напоминание: у вас тренировка сегодня"
    assert_includes text, Date.current.strftime("%d.%m.%Y")
    assert_includes text, " — С тренером\n"
  end

  test "localizes game reminder in Spanish" do
    text = reminder_text(with_coach: true, locale: "es")

    assert_includes text, "Recordatorio: tienes un entrenamiento hoy"
    assert_includes text, Date.current.strftime("%d/%m/%Y")
    assert_includes text, " — Con entrenador\n"
  end

  test "omits coach mark from game reminder without coach" do
    text = reminder_text(with_coach: false)

    assert_includes text, "Reminder: you have a game today"
    assert_not_includes text.lines.first, " — With coach"
    assert text.lines.first.chomp.end_with?(".")
  end

  test "names the coach and the training programme" do
    coach = create_coach("named-coach-reminder@example.com", 93_010, name: "Иван Петров")
    game = training_with(coaches: [ coach ], blocks: [ "Разминка", "Подача" ])
    text = telegram_reminder_for(game, users(:one), locale: "ru")

    assert_includes text, " — С тренером Иван Петров\n"
    assert_includes text, "Программа: Разминка, Подача"
  ensure
    coach&.destroy
  end

  test "names the coach by telegram handle like a participant" do
    coach = create_coach("handle-coach-reminder@example.com", 93_013, name: "Иван Петров")
    coach.update!(telegram_username: "coach_ivan")
    game = training_with(coaches: [ coach ])
    text = telegram_reminder_for(game, users(:one), locale: "ru")

    assert_includes text, " — С тренером @coach_ivan\n"
  ensure
    coach&.destroy
  end

  test "names both coaches of a training" do
    first = create_coach("first-coach-reminder@example.com", 93_011, name: "Иван Петров")
    second = create_coach("second-coach-reminder@example.com", 93_012, name: "Пётр Иванов")
    game = training_with(coaches: [ first, second ])
    text = telegram_reminder_for(game, users(:one), locale: "ru")

    assert_includes text, " — С тренерами Иван Петров, Пётр Иванов\n"
  ensure
    first&.destroy
    second&.destroy
  end

  test "names people by name in an email reminder" do
    coach = create_coach("email-coach-reminder@example.com", 93_014, name: "Иван Петров")
    coach.update!(telegram_username: "coach_ivan")
    game = training_with(coaches: [ coach ])
    recipient = users(:one)
    recipient.update!(
      email: "email-reminder@example.com",
      name: "Пётр Игрок",
      telegram_username: "player_petr",
      notification_channel: "email",
      locale: "ru"
    )
    game.participations.create!(user: recipient)

    perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) { GameReminderJob.perform_now }
    body = mail_text(ActionMailer::Base.deliveries.find { |mail| mail.to.include?(recipient.email) })

    assert_includes body, "С тренером Иван Петров"
    assert_includes body, "Пётр Игрок"
    assert_not_includes body, "@coach_ivan"
    assert_not_includes body, "@player_petr"
  ensure
    coach&.destroy
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

    assert_includes coach_text, "training today"
  end

  test "reminds coach a day ahead at 14 for an early game" do
    coach_text = coach_reminder_text(time: "10:00", booking_date: Date.tomorrow)

    assert_includes coach_text, "training tomorrow"
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

    assert_includes calls.find { |call| call.first == coach.telegram_chat_id }.second, "training today"
  ensure
    coach&.destroy
  end

  test "makes the court name a link in the telegram reminder" do
    coach = create_coach("court-link-reminder@example.com", 93_020, name: "Иван Петров")
    game = training_with(coaches: [ coach ])
    text = telegram_reminder_for(game, users(:one), locale: "ru")

    assert_includes text, %(<a href="https://getcourt.co/courts/#{courts(:one).id}">#{courts(:one).name}</a>)
  ensure
    coach&.destroy
  end

  test "escapes what people typed in the telegram reminder" do
    coach = create_coach("court-escape-reminder@example.com", 93_021, name: "Смит & сыновья")
    game = training_with(coaches: [ coach ], blocks: [ "Подача <сильно>" ])
    text = telegram_reminder_for(game, users(:one), locale: "ru")

    assert_includes text, "Смит &amp; сыновья"
    assert_includes text, "Подача &lt;сильно&gt;"
    assert_not_includes text, "<сильно>"
  ensure
    coach&.destroy
  end

  test "keeps the email reminder free of markup" do
    coach = create_coach("court-plain-reminder@example.com", 93_022, name: "Иван Петров")
    game = training_with(coaches: [ coach ])
    recipient = users(:one)
    recipient.update!(
      email: "court-plain-recipient@example.com",
      notification_channel: "email",
      locale: "ru"
    )
    game.participations.create!(user: recipient)

    perform_enqueued_jobs { GameReminderJob.perform_now }
    body = mail_text(ActionMailer::Base.deliveries.find { |mail| mail.to.include?(recipient.email) })

    # В письме кнопки — свои ссылки, а вот корт должен остаться просто именем.
    assert_includes body, "на корте #{courts(:one).name}"
    assert_not_includes body, "/courts/#{courts(:one).id}"
  ensure
    coach&.destroy
  end

  private
    def mail_text(mail)
      mail.multipart? ? mail.parts.map { |part| part.body.decoded }.join("\n") : mail.body.decoded
    end

    def create_coach(email, chat_id, name:)
      User.create!(
        email: email,
        name: name,
        coach: true,
        telegram_chat_id: chat_id,
        notification_channel: "telegram",
        telegram_locale: "ru"
      )
    end

    # Приглашения остаются неотвеченными: в напоминании тренер уже назван, раз его выбрали.
    def training_with(coaches:, blocks: [])
      game = Game.create!(
        court: courts(:one),
        user: users(:two),
        with_coach: true,
        coach: coaches.first,
        second_coach: coaches.second,
        date: Date.current,
        time: "18:00"
      )
      block_ids = blocks.map { |title| TrainingBlock.create!(user: coaches.first, title: title).id }
      game.replace_training_plan!(block_ids) if block_ids.any?
      game
    end

    def telegram_reminder_for(game, recipient, locale:)
      recipient.update!(
        email: "programme-reminder-#{recipient.id}@example.com",
        telegram_chat_id: 90_007,
        telegram_locale: locale,
        notification_channel: "telegram"
      )
      game.participations.create!(user: recipient)
      calls = []

      stub_singleton(SendTelegramNotificationJob, :perform_later, ->(*args) { calls << args }) do
        GameReminderJob.perform_now
      end

      calls.find { |call| call.second.include?("/games/#{game.id}") }.second
    end

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
