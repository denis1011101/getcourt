require "test_helper"

class NotifyUrgentPlayerSearchJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  test "notifies only opted-in nearby users and excludes owner" do
    owner = User.create!(
      email: "owner_urgent_test@example.com",
      name: "Owner",
      telegram_chat_id: "1001",
      telegram_username: "owner_test",
      city_name: "Yekaterinburg"
    )
    court = Court.create!(name: "Center Court", city_name: "Yekaterinburg")
    game = Game.create!(
      court: court,
      user: owner,
      date: Date.current + 1.day,
      time: "20:00",
      sport: "Tennis",
      skill_level: "advanced",
      urgent_player_search: true
    )

    nearby = User.create!(
      email: "nearby_urgent_test@example.com",
      name: "Nearby",
      telegram_chat_id: "2001",
      city_name: "Yekaterinburg",
      notify_nearby: true,
      notification_channel: "telegram",
      telegram_locale: "ru"
    )
    User.create!(
      email: "nearby_email_urgent_test@example.com",
      name: "Nearby Email",
      city_name: "Yekaterinburg",
      notify_nearby: true,
      notification_channel: "email",
      locale: "en"
    )
    User.create!(
      email: "other_city_urgent_test@example.com",
      name: "Other City",
      telegram_chat_id: "2002",
      city_name: "Moscow",
      notify_nearby: true,
      notification_channel: "telegram",
      telegram_locale: "ru"
    )
    User.create!(
      email: "missing_city_urgent_test@example.com",
      name: "Missing City",
      telegram_chat_id: "2004",
      notify_nearby: true,
      notification_channel: "telegram",
      telegram_locale: "ru"
    )
    User.create!(
      email: "optout_urgent_test@example.com",
      name: "Opt Out",
      telegram_chat_id: "2003",
      city_name: "Yekaterinburg",
      notify_nearby: false,
      notification_channel: "telegram",
      telegram_locale: "ru"
    )

    calls = []
    assert_enqueued_emails 1 do
      with_stubbed_singleton_method(SendTelegramNotificationJob, :perform_later, ->(*args, **kwargs) { calls << { args: args, kwargs: kwargs } }) do
        NotifyUrgentPlayerSearchJob.perform_now(game.id)
      end
    end

    assert_equal 1, calls.size
    assert_equal nearby.telegram_chat_id, calls[0][:args][0]
    assert_nil calls[0][:kwargs][:parse_mode]
    assert_includes calls[0][:args][1], "Игра ##{game.id}"
    assert_includes calls[0][:args][1], "@owner_test"
    assert_includes calls[0][:args][1], "Теннис"
    assert_includes calls[0][:args][1], "Продвинутый"
    assert_includes calls[0][:args][1], "Center Court"
    assert_includes calls[0][:args][1], "https://getcourt.co/games/#{game.id}"
    assert_includes calls[0][:args][1], "Отключить эти уведомления: https://getcourt.co/account/notifications"
  end

  test "falls back to email when telegram is selected but not connected" do
    owner = User.create!(email: "owner_no_fallback@example.com", city_name: "Yekaterinburg")
    recipient = User.create!(
      email: "recipient_no_fallback@example.com",
      city_name: "Yekaterinburg",
      notify_nearby: true,
      notification_channel: "telegram"
    )
    court = Court.create!(name: "No Fallback Court", city_name: "Yekaterinburg")
    game = Game.create!(court: court, user: owner, date: Date.current + 1.day, urgent_player_search: true)
    calls = []

    assert_enqueued_emails 1 do
      with_stubbed_singleton_method(SendTelegramNotificationJob, :perform_later, ->(*args, **kwargs) { calls << { args: args, kwargs: kwargs } }) do
        NotifyUrgentPlayerSearchJob.perform_now(game.id)
      end
    end

    assert_empty calls
  ensure
    game&.destroy
    court&.destroy
    recipient&.destroy
    owner&.destroy
  end

  test "does not email generated telegram address" do
    owner = User.create!(email: "owner_generated_email@example.com", city_name: "Yekaterinburg")
    recipient = User.create!(
      email: "tg-#{SecureRandom.hex(8)}@telegram.getcourt",
      telegram_generated_email: true,
      city_name: "Yekaterinburg",
      notify_nearby: true,
      notification_channel: "email"
    )
    court = Court.create!(name: "Generated Email Court", city_name: "Yekaterinburg")
    game = Game.create!(court: court, user: owner, date: Date.current + 1.day, urgent_player_search: true)

    assert_no_enqueued_emails do
      NotifyUrgentPlayerSearchJob.perform_now(game.id)
    end
  ensure
    game&.destroy
    court&.destroy
    recipient&.destroy
    owner&.destroy
  end

  test "does not notify anyone when the game court has no city" do
    owner = User.create!(email: "owner_without_game_city@example.com")
    recipient = User.create!(
      email: "recipient_without_game_city@example.com",
      city_name: "Yekaterinburg",
      notify_nearby: true,
      notification_channel: "email"
    )
    court = Court.create!(name: "Court Without City")
    game = Game.create!(court: court, user: owner, date: Date.current + 1.day, urgent_player_search: true)
    calls = []

    assert_no_enqueued_emails do
      with_stubbed_singleton_method(SendTelegramNotificationJob, :perform_later, ->(*args, **kwargs) { calls << { args: args, kwargs: kwargs } }) do
        NotifyUrgentPlayerSearchJob.perform_now(game.id)
      end
    end

    assert_empty calls
  ensure
    game&.destroy
    court&.destroy
    recipient&.destroy
    owner&.destroy
  end

  test "does not notify when game players search is disabled" do
    game = games(:one)
    game.update!(urgent_player_search: false)

    calls = []
    with_stubbed_singleton_method(SendTelegramNotificationJob, :perform_later, ->(*args, **kwargs) { calls << { args: args, kwargs: kwargs } }) do
      NotifyUrgentPlayerSearchJob.perform_now(game.id)
    end

    assert_empty calls
  end

  test "notifies users when city matches through alias in either direction" do
    owner = User.create!(email: "owner_alias@example.com", city_name: "Yekaterinburg")
    court_latin = Court.create!(name: "Latin Court", city_name: "Yekaterinburg")
    court_cyrillic = Court.create!(name: "Cyrillic Court", city_name: "Екатеринбург")

    user_latin_ekat = User.create!(
      email: "ekat_latin@example.com",
      city_name: "Ekaterinburg",
      notify_nearby: true,
      notification_channel: "telegram",
      telegram_chat_id: "5001"
    )
    user_cyrillic = User.create!(
      email: "ekat_cyrillic@example.com",
      city_name: "Екатеринбург",
      notify_nearby: true,
      notification_channel: "telegram",
      telegram_chat_id: "5002"
    )
    user_yekat = User.create!(
      email: "yekat_user@example.com",
      city_name: "Yekaterinburg",
      notify_nearby: true,
      notification_channel: "telegram",
      telegram_chat_id: "5003"
    )

    game_latin = Game.create!(court: court_latin, user: owner, date: Date.current + 1.day, urgent_player_search: true)
    calls = []
    with_stubbed_singleton_method(SendTelegramNotificationJob, :perform_later, ->(*args, **kwargs) { calls << args.first }) do
      NotifyUrgentPlayerSearchJob.perform_now(game_latin.id)
    end
    assert_equal %w[5001 5002 5003].sort, calls.map(&:to_s).sort

    game_cyrillic = Game.create!(court: court_cyrillic, user: owner, date: Date.current + 1.day, urgent_player_search: true)
    calls = []
    with_stubbed_singleton_method(SendTelegramNotificationJob, :perform_later, ->(*args, **kwargs) { calls << args.first }) do
      NotifyUrgentPlayerSearchJob.perform_now(game_cyrillic.id)
    end
    assert_equal %w[5001 5002 5003].sort, calls.map(&:to_s).sort
  ensure
    game_latin&.destroy
    game_cyrillic&.destroy
    court_latin&.destroy
    court_cyrillic&.destroy
    user_latin_ekat&.destroy
    user_cyrillic&.destroy
    user_yekat&.destroy
    owner&.destroy
  end

  test "delivers to telegram when notification_channel is nil but telegram_chat_id is present" do
    owner = User.create!(email: "owner_legacy_tg@example.com", city_name: "Yekaterinburg")
    court = Court.create!(name: "Legacy TG Court", city_name: "Yekaterinburg")
    game = Game.create!(court: court, user: owner, date: Date.current + 1.day, urgent_player_search: true)
    recipient = User.new(
      name: "Legacy User",
      city_name: "Yekaterinburg",
      notify_nearby: true,
      telegram_chat_id: "6001",
      notification_channel: nil
    )
    recipient.save(validate: false)

    calls = []
    assert_no_enqueued_emails do
      with_stubbed_singleton_method(SendTelegramNotificationJob, :perform_later, ->(*args, **kwargs) { calls << args.first }) do
        NotifyUrgentPlayerSearchJob.perform_now(game.id)
      end
    end

    assert_equal [ "6001" ], calls.map(&:to_s)
  ensure
    game&.destroy
    court&.destroy
    recipient&.destroy
    owner&.destroy
  end

  test "delivers to email when notification_channel is explicitly email even if telegram is connected" do
    owner = User.create!(email: "owner_explicit_email@example.com", city_name: "Yekaterinburg")
    court = Court.create!(name: "Explicit Email Court", city_name: "Yekaterinburg")
    game = Game.create!(court: court, user: owner, date: Date.current + 1.day, urgent_player_search: true)
    recipient = User.create!(
      email: "explicit_email_recipient@example.com",
      city_name: "Yekaterinburg",
      notify_nearby: true,
      telegram_chat_id: "7001",
      notification_channel: "email"
    )

    calls = []
    assert_enqueued_emails 1 do
      with_stubbed_singleton_method(SendTelegramNotificationJob, :perform_later, ->(*args, **kwargs) { calls << args.first }) do
        NotifyUrgentPlayerSearchJob.perform_now(game.id)
      end
    end

    assert_empty calls
  ensure
    game&.destroy
    court&.destroy
    recipient&.destroy
    owner&.destroy
  end

  test "does not enqueue any jobs when user has no email and no telegram_chat_id" do
    owner = User.create!(email: "owner_no_contact@example.com", city_name: "Yekaterinburg")
    court = Court.create!(name: "No Contact Court", city_name: "Yekaterinburg")
    game = Game.create!(court: court, user: owner, date: Date.current + 1.day, urgent_player_search: true)
    recipient = User.new(
      name: "Nameless Contactless",
      city_name: "Yekaterinburg",
      notify_nearby: true,
      email: nil,
      telegram_chat_id: nil,
      notification_channel: nil
    )
    recipient.save(validate: false)

    calls = []
    assert_no_enqueued_emails do
      with_stubbed_singleton_method(SendTelegramNotificationJob, :perform_later, ->(*args, **kwargs) { calls << args.first }) do
        NotifyUrgentPlayerSearchJob.perform_now(game.id)
      end
    end

    assert_empty calls
  ensure
    game&.destroy
    court&.destroy
    recipient&.destroy
    owner&.destroy
  end

  test "notifications_url returns base host for default host and custom host otherwise" do
    job = NotifyUrgentPlayerSearchJob.new

    assert_equal "https://getcourt.co/account/notifications", job.send(:notifications_url)

    with_env("APP_HOST", "https://custom.getcourt.co/") do
      assert_equal "https://custom.getcourt.co/account/notifications", job.send(:notifications_url)
    end
  end

  test "interpolates telegram notification text in all locales" do
    job = NotifyUrgentPlayerSearchJob.new
    notifications_url = job.send(:notifications_url)

    %w[ru en es].each do |locale|
      text = Telegram::I18n.t(
        :urgent_search_notification,
        locale: locale,
        id: 123,
        owner: "Player1",
        date: "10.11.2026 20:00",
        sport: "Tennis",
        skill: "Intermediate",
        court: "Center Court",
        url: "https://getcourt.co/games/123",
        notifications_url: notifications_url
      )

      assert_includes text, notifications_url
      refute_includes text, "%{"
    end
  end

  test "matches by city_id when both have city_id, ignoring string names" do
    city1 = City.create!(name: "Springfield", country_code: "US")
    city2 = City.create!(name: "Springfield", country_code: "CA")

    owner = User.create!(email: "owner_city_id@example.com", city_id: city1.id)
    court = Court.create!(name: "Court ID", city_id: city1.id, country_code: "US", city_name: "Springfield")
    game = Game.create!(court: court, user: owner, date: Date.current + 1.day, urgent_player_search: true)

    same_id_user = User.create!(
      email: "same_id@example.com",
      city_id: city1.id,
      city_name: "Completely Different Name",
      notify_nearby: true,
      notification_channel: "telegram",
      telegram_chat_id: "8001"
    )
    diff_id_same_name_user = User.create!(
      email: "diff_id@example.com",
      city_id: city2.id,
      city_name: "Springfield",
      notify_nearby: true,
      notification_channel: "telegram",
      telegram_chat_id: "8002"
    )

    calls = []
    with_stubbed_singleton_method(SendTelegramNotificationJob, :perform_later, ->(*args, **kwargs) { calls << args.first }) do
      NotifyUrgentPlayerSearchJob.perform_now(game.id)
    end

    assert_equal [ "8001" ], calls.map(&:to_s)
  ensure
    game&.destroy
    court&.destroy
    same_id_user&.destroy
    diff_id_same_name_user&.destroy
    owner&.destroy
    city1&.destroy
    city2&.destroy
  end

  test "delivers when court has city_id and blank city_name" do
    city = City.create!(name: "Only ID City", country_code: "US")
    owner = User.create!(email: "owner_blank_court_name@example.com", city_id: city.id)
    court = Court.create!(name: "Blank Name Court", city_id: city.id, country_code: "US", city_name: nil)
    game = Game.create!(court: court, user: owner, date: Date.current + 1.day, urgent_player_search: true)

    recipient = User.create!(
      email: "recipient_city_id@example.com",
      city_id: city.id,
      notify_nearby: true,
      notification_channel: "telegram",
      telegram_chat_id: "8003"
    )

    calls = []
    with_stubbed_singleton_method(SendTelegramNotificationJob, :perform_later, ->(*args, **kwargs) { calls << args.first }) do
      NotifyUrgentPlayerSearchJob.perform_now(game.id)
    end

    assert_equal [ "8003" ], calls.map(&:to_s)
  ensure
    game&.destroy
    court&.destroy
    recipient&.destroy
    owner&.destroy
    city&.destroy
  end

  test "keeps distinct non-transliterated cities without IDs apart" do
    owner = User.create!(email: "owner_cjk@example.com", city_name: "北京")
    court = Court.create!(name: "Beijing Court", city_name: "北京")
    game = Game.create!(court: court, user: owner, date: Date.current + 1.day, urgent_player_search: true)

    beijing_user = User.create!(
      email: "beijing_user@example.com",
      city_name: "北京",
      notify_nearby: true,
      notification_channel: "telegram",
      telegram_chat_id: "8004"
    )
    shanghai_user = User.create!(
      email: "shanghai_user@example.com",
      city_name: "上海",
      notify_nearby: true,
      notification_channel: "telegram",
      telegram_chat_id: "8005"
    )

    calls = []
    with_stubbed_singleton_method(SendTelegramNotificationJob, :perform_later, ->(*args, **kwargs) { calls << args.first }) do
      NotifyUrgentPlayerSearchJob.perform_now(game.id)
    end

    assert_equal [ "8004" ], calls.map(&:to_s)
  ensure
    game&.destroy
    court&.destroy
    beijing_user&.destroy
    shanghai_user&.destroy
    owner&.destroy
  end

  private

  def with_env(key, value)
    original = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = original
  end

  def with_stubbed_singleton_method(target, method_name, replacement)
    singleton = target.singleton_class
    had_method = singleton.method_defined?(method_name) || singleton.private_method_defined?(method_name)
    original = singleton.instance_method(method_name) if had_method
    callable = replacement.respond_to?(:call) ? replacement : ->(*) { replacement }

    singleton.define_method(method_name) do |*args, **kwargs, &block|
      callable.call(*args, **kwargs, &block)
    end

    yield
  ensure
    if had_method
      singleton.define_method(method_name, original)
    else
      singleton.remove_method(method_name)
    end
  end
end
