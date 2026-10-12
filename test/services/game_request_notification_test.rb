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

  test "participation added names the game with date and who added, without email" do
    user = User.create!(email: "added-player@example.com", telegram_chat_id: 98_766, telegram_locale: "ru", notification_channel: "telegram")
    actor = User.create!(email: "actor-secret@example.com", name: "Denis", telegram_username: "denis_actor")
    game = games(:one)
    calls = []

    stub_singleton(SendTelegramNotificationJob, :perform_later, ->(*args, **kwargs) { calls << [ args, kwargs ] }) do
      GameRequestNotification.participation_added(user: user, game: game, by: actor)
    end

    text = calls.first.first.second
    assert_includes text, Telegram::Chat::Message.game_label(game, locale: "ru")
    assert_includes text, "Кто добавил: Denis (@denis_actor)."
    assert_not_includes text, "actor-secret@example.com"
  ensure
    user&.destroy
    actor&.destroy
  end

  test "prebooking assigned without a name or nick skips the by-line" do
    user = User.create!(email: "assigned-player@example.com", telegram_chat_id: 98_767, telegram_locale: "ru", notification_channel: "telegram")
    actor = User.create!(email: "anon-actor@example.com")
    date = Date.current + 3.days
    calls = []

    stub_singleton(SendTelegramNotificationJob, :perform_later, ->(*args, **kwargs) { calls << [ args, kwargs ] }) do
      GameRequestNotification.prebooking_assigned(user: user, game: games(:one), date: date, by: actor)
    end

    text = calls.first.first.second
    assert_includes text, "на будущую игру ##{games(:one).id}"
    assert_includes text, I18n.l(date, format: :telegram, locale: "ru")
    assert_not_includes text, "Кто записал"
    assert_not_includes text, "anon-actor@example.com"
  ensure
    user&.destroy
    actor&.destroy
  end

  test "assigned and added notifications localize subjects and texts in every locale" do
    user = User.create!(email: "locales-player@example.com")
    actor = User.create!(email: "locales-actor@example.com", name: "Denis")
    game = games(:one)
    game.court.update_column(:city_name, "Yekaterinburg")
    date = Date.current + 3.days
    notifications = []

    stub_singleton(NotificationDelivery, :deliver, ->(user:, notification:) { notifications << notification }) do
      GameRequestNotification.participation_added(user: user, game: game, by: actor)
      GameRequestNotification.prebooking_assigned(user: user, game: game, date: date, by: actor)
    end
    added, assigned = notifications

    {
      "en" => [ "Added by: Denis.", "Booked by: Denis.", "upcoming Game" ],
      "es" => [ "Te añadió: Denis.", "Te reservó: Denis.", "próximo partido" ],
      "ru" => [ "Кто добавил: Denis.", "Кто записал: Denis.", "будущую игру" ]
    }.each do |locale, (added_by, assigned_by, upcoming)|
      label = Telegram::Chat::Message.game_label(game, locale: locale)
      assert_includes label, "##{game.id} Yekaterinburg"
      assert_includes added.subject(locale), label
      assert_includes added.body(locale), "#{label}."
      assert_includes added.body(locale), added_by

      assert_includes assigned.subject(locale), "#{upcoming} ##{game.id} Yekaterinburg — "
      assert_includes assigned.body(locale), "#{upcoming} ##{game.id} Yekaterinburg — "
      assert_includes assigned.subject(locale), I18n.l(date, format: :long, locale: locale)
      assert_includes assigned.body(locale), I18n.l(date, format: :telegram, locale: locale)
      assert_includes assigned.body(locale), assigned_by
      assert_no_match(/translation missing|%\{/i, added.subject(locale) + added.body(locale) + assigned.subject(locale) + assigned.body(locale))
    end
  ensure
    user&.destroy
    actor&.destroy
  end
end
