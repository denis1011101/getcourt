require "test_helper"

class Telegram::ParticipationNotifierTest < ActiveSupport::TestCase
  test "guest notification uses guest name without telegram handle" do
    owner = User.create!(email: "guest_notify_owner@example.com", telegram_chat_id: "123", telegram_username: "owner", telegram_locale: "en")
    game = Game.create!(court: courts(:one), user: owner, date: Date.tomorrow, time: "10:00")
    participation = Participation.create!(game: game, guest_name: "Alex Guest", status: "approved")
    calls = []

    stub_singleton(SendTelegramNotificationJob, :perform_later, ->(*args) { calls << args }) do
      Telegram::ParticipationNotifier.notify_owner(game, participation, action: :removed)
    end

    assert_equal 1, calls.size
    text = calls.first.second
    assert_includes text, "Alex Guest (guest)"
    assert_not_includes text, "@"
  end
end
