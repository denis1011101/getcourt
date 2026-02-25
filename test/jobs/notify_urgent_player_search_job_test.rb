require "test_helper"

class NotifyUrgentPlayerSearchJobTest < ActiveJob::TestCase
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
      telegram_locale: "ru"
    )
    User.create!(
      email: "other_city_urgent_test@example.com",
      name: "Other City",
      telegram_chat_id: "2002",
      city_name: "Moscow",
      notify_nearby: true,
      telegram_locale: "ru"
    )
    User.create!(
      email: "optout_urgent_test@example.com",
      name: "Opt Out",
      telegram_chat_id: "2003",
      city_name: "Yekaterinburg",
      notify_nearby: false,
      telegram_locale: "ru"
    )

    calls = []
    with_stubbed_singleton_method(SendTelegramNotificationJob, :perform_later, ->(*args, **kwargs) { calls << { args: args, kwargs: kwargs } }) do
      NotifyUrgentPlayerSearchJob.perform_now(game.id)
    end

    assert_equal 1, calls.size
    assert_equal nearby.telegram_chat_id, calls[0][:args][0]
    assert_nil calls[0][:kwargs][:parse_mode]
    assert_includes calls[0][:args][1], "Игра ##{game.id}"
    assert_includes calls[0][:args][1], "@owner_test"
    assert_includes calls[0][:args][1], "Tennis"
    assert_includes calls[0][:args][1], "Advanced"
    assert_includes calls[0][:args][1], "Center Court"
  end

  test "does not notify when game urgent search is disabled" do
    game = games(:one)
    game.update!(urgent_player_search: false)

    calls = []
    with_stubbed_singleton_method(SendTelegramNotificationJob, :perform_later, ->(*args, **kwargs) { calls << { args: args, kwargs: kwargs } }) do
      NotifyUrgentPlayerSearchJob.perform_now(game.id)
    end

    assert_empty calls
  end

  private

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
