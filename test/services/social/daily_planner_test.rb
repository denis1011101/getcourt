require "test_helper"

class Social::DailyPlannerTest < ActiveSupport::TestCase
  include CacheHelper

  setup do
    @court = Court.create!(name: "Planner Court", city_name: "Yekaterinburg", coordinates: "56.83, 60.60",
                           moderation_status: "approved", approved_at: 1.day.ago)
    @user = User.create!(email: "planner_owner@example.com", name: "Denis Levenko")
    @rival = User.create!(email: "planner_rival@example.com", name: "Ivan Petrov")
  end

  test "picks tomorrow's game with the most free spots" do
    Game.destroy_all
    small = Game.create!(court: @court, user: @user, date: Date.tomorrow, time: "18:00", sport: "Tennis", players_count: 2)
    big = Game.create!(court: @court, user: @user, date: Date.tomorrow, time: "20:00", sport: "Tennis", players_count: 4)

    content = Social::DailyPlanner.new.pick

    assert_equal "upcoming:#{big.id}:#{Date.current.iso8601}", content.dedup_key
    assert_not_equal small.id.to_s, content.subject
    assert_includes content.text(locale: :en), "4 spots left"
  end

  test "a game with no free spots is not offered" do
    Game.destroy_all
    game = Game.create!(court: @court, user: @user, date: Date.tomorrow, time: "18:00", sport: "Tennis", players_count: 1)
    Participation.create!(game: game, user: @rival, status: "approved")

    assert_not_equal "upcoming", Social::DailyPlanner.new.pick&.variant
  end

  test "upcoming content becomes unavailable when the game is cancelled after planning" do
    Game.destroy_all
    game = Game.create!(court: @court, user: @user, date: Date.tomorrow, time: "18:00",
                        sport: "Tennis", players_count: 4)
    content = Social::DailyPlanner.new.pick

    game.prebooking_cancellations.create!(date: Date.tomorrow, user: @user)

    assert_equal game.id.to_s, content.subject
    assert_not content.available?
  end

  test "moves on to yesterday's result once upcoming has just been posted" do
    Game.destroy_all
    Match.destroy_all
    match = Match.create!(user: @user, opponent: @rival, mode: "singles", outcome: "win",
                          played_at: 1.day.ago, score: "6-4 6-3", surface: "clay")

    content = Social::DailyPlanner.new.pick

    assert_equal "result", content.variant
    assert_equal match.id.to_s, content.subject
    assert_includes content.text(locale: :en), "6-4 6-3"
    assert_includes content.text(locale: :en), "Denis L."
    assert_includes content.text(locale: :en), "Clay"
  end

  test "mirrored rows of the same match give a single candidate" do
    Game.destroy_all
    Match.destroy_all
    played_at = 1.day.ago.change(usec: 0)
    first = Match.create!(user: @user, opponent: @rival, mode: "singles", outcome: "win",
                          played_at: played_at, score: "6-4 6-3")
    Match.create!(user: @rival, opponent: @user, mode: "singles", outcome: "loss",
                  played_at: played_at, score: "6-4 6-3")

    assert_equal first.id.to_s, Social::DailyPlanner.new.pick.subject
  end

  test "a draw has no winner and is skipped" do
    Game.destroy_all
    Match.destroy_all
    Match.create!(user: @user, opponent: @rival, mode: "singles", outcome: "draw",
                  played_at: 1.day.ago, score: "6-4 4-6")

    assert_not_equal "result", Social::DailyPlanner.new.pick&.variant
  end

  test "falls back to a fact and never repeats a variant two days running" do
    with_memory_cache do
      Game.destroy_all
      Match.destroy_all

      today = Social::DailyPlanner.new.pick
      assert_equal "fact", today.variant

      SocialPost.create!(network: "bluesky", kind: "daily", dedup_key: today.dedup_key,
                         external_post_id: "1", posted_at: Time.current)
      tomorrow = Social::DailyPlanner.new(date: Date.current + 1).pick

      assert_not_equal today.subject, tomorrow.subject
    end
  end

  test "stays silent when every fact is still cooling down" do
    with_memory_cache do
      Game.destroy_all
      Match.destroy_all

      TennisLife::Feed::Sources::Facts::KEYS.each do |key|
        SocialPost.create!(network: "bluesky", kind: "daily", dedup_key: "fact:#{key}:#{Date.current}",
                           external_post_id: key, posted_at: 2.days.ago)
      end

      assert_nil Social::DailyPlanner.new.pick
    end
  end

  test "a fact cooled down long enough comes back" do
    with_memory_cache do
      Game.destroy_all
      Match.destroy_all

      TennisLife::Feed::Sources::Facts::KEYS.each do |key|
        SocialPost.create!(network: "bluesky", kind: "daily", dedup_key: "fact:#{key}:#{30.days.ago.to_date}",
                           external_post_id: key, posted_at: 30.days.ago)
      end

      assert_equal "fact", Social::DailyPlanner.new.pick&.variant
    end
  end
end
