require "test_helper"

class RecentCommitsRegressionApiTest < ActiveSupport::TestCase
  test "delete_message delegates to Telegram API with normalized params" do
    captured = nil
    original_post = Telegram::Api.method(:post)

    Telegram::Api.define_singleton_method(:post) do |path, params|
      captured = [ path, params ]
    end

    Telegram::Api.delete_message(123, "456")

    assert_equal [ "deleteMessage", { "chat_id" => "123", "message_id" => 456 } ], captured
  ensure
    Telegram::Api.define_singleton_method(:post, original_post)
  end
end

class RecentCommitsRegressionUpsertMatchForGameServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @actor = users(:two)
    @game = games(:one)
  end

  test "reuses existing match from the same day" do
    existing = Match.create!(
      user: @user,
      game: @game,
      mode: "singles",
      outcome: "loss",
      played_at: Time.zone.parse("2026-02-17 09:00"),
      stats: {}
    )

    service = PlayerStatistics::UpsertMatchForGameService.new(
      user: @user,
      game: @game,
      actor: @actor,
      mode: "singles",
      outcome: "win",
      played_at: Time.zone.parse("2026-02-17 21:30")
    )

    returned = service.call

    assert_equal existing.id, returned.id
    assert_equal 1, Match.where(user: @user, game: @game, mode: "singles").where(played_at: Time.zone.parse("2026-02-17").all_day).count
  end
end

class RecentCommitsRegressionTennisLifeControllerConfigTest < ActiveSupport::TestCase
  test "configured channel usernames include tennisologia and lowercase matching is possible" do
    usernames = TennisLifeController::TELEGRAM_CHANNELS.map { |c| c[:username].to_s.delete_prefix("@").downcase }

    assert_includes usernames, "tennisologia"
    assert_equal "@tennisologia", TennisLifeController::TELEGRAM_CHANNELS.find { |c| c[:name] == "Теннисология" }[:username]
  end
end
