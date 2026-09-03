require "test_helper"

class ParticipationNotifierTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "guest notification uses guest name without telegram handle" do
    owner = User.create!(email: "guest_notify_owner@example.com", telegram_chat_id: "123", telegram_username: "owner", telegram_locale: "en")
    game = Game.create!(court: courts(:one), user: owner, date: Date.tomorrow, time: "10:00")
    participation = Participation.create!(game: game, guest_name: "Alex Guest", status: "approved")
    calls = []

    stub_singleton(SendTelegramNotificationJob, :perform_later, ->(*args) { calls << args }) do
      ParticipationNotifier.notify_owner(game, participation, action: :removed)
    end

    assert_equal 1, calls.size
    text = calls.first.second
    assert_includes text, "Alex Guest (guest)"
    assert_not_includes text, "@"
  end

  test "training notification says training, not game" do
    owner = User.create!(email: "training_notify_owner@example.com", telegram_chat_id: "124", telegram_username: "owner", telegram_locale: "ru")
    game = Game.create!(court: courts(:one), user: owner, date: Date.tomorrow, time: "10:00", kind: "training")
    joiner = User.create!(email: "training_joiner@example.com", telegram_username: "joiner")
    calls = []

    stub_singleton(SendTelegramNotificationJob, :perform_later, ->(*args) { calls << args }) do
      ParticipationNotifier.notify_owner(game, joiner, action: :joined)
    end

    assert_includes calls.first.second, "присоединился к вашей тренировке"
  end

  test "uses email when owner selected email notifications" do
    owner = User.create!(email: "participation_email_owner@example.com", notification_channel: "email", locale: "en")
    game = Game.create!(court: courts(:one), user: owner, date: Date.tomorrow, time: "10:00")

    assert_enqueued_emails 1 do
      ParticipationNotifier.notify_owner(game, "Alex", action: :requested)
    end
  end
end
