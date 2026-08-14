require "test_helper"

class GameChangeNotificationJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  # The debounce keeps its pending changes in Rails.cache, which is a null store in
  # tests — give this one a real store so the collecting behaviour is exercised.
  setup do
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @owner = users(:one)
    @participant = User.create!(email: "debounced-participant@example.com", notification_channel: "email", locale: "en")
    @game = Game.create!(court: courts(:one), user: @owner, date: Date.current + 3.days, time: "18:00")
    @game.participations.create!(user: @participant)
  end

  teardown do
    Rails.cache = @previous_cache
  end

  test "a run of field-by-field edits schedules one job and one message" do
    assert_enqueued_jobs 1, only: GameChangeNotificationJob do
      @game.update!(time: "19:00")
      GameChangeNotificationJob.schedule(@game, @owner, @game.saved_changes)

      @game.update!(players_count: 2)
      GameChangeNotificationJob.schedule(@game, @owner, @game.saved_changes)
    end

    assert_enqueued_emails 1 do
      GameChangeNotificationJob.perform_now(@game.id, @owner.id)
    end
  end

  test "keeps the value participants last saw and drops fields edited back" do
    merged = GameChangeNotificationJob.merge_changes(
      { "time" => [ "18:00", "19:00" ] },
      { "time" => [ "19:00", "20:00" ] }
    )

    assert_equal [ "18:00", "20:00" ], merged["time"]

    reverted = GameChangeNotificationJob.merge_changes(
      { "time" => [ "18:00", "19:00" ] },
      { "time" => [ "19:00", "18:00" ] }
    )

    assert_empty reverted
  end

  test "ignores fields nobody plans around" do
    assert_no_enqueued_jobs only: GameChangeNotificationJob do
      GameChangeNotificationJob.schedule(@game, @owner, { "urgent_player_search" => [ false, true ] })
    end
  end
end
