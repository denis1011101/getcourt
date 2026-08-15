require "test_helper"

class FeaturedMatchTest < ActiveSupport::TestCase
  test "current returns the active upcoming match" do
    match = FeaturedMatch.create!(valid_attributes(starts_at: 2.hours.from_now, active: true))

    assert_equal match, FeaturedMatch.current.first
  end

  test "current ignores started active matches" do
    FeaturedMatch.create!(valid_attributes(starts_at: 1.hour.ago, active: true))

    assert_nil FeaturedMatch.current.first
  end

  test "banner returns the active match after kickoff" do
    match = FeaturedMatch.create!(valid_attributes(starts_at: 1.hour.ago, active: true))

    assert_equal match, FeaturedMatch.banner.first
  end

  test "banner returns the active match once finished" do
    match = FeaturedMatch.create!(valid_attributes(starts_at: 1.day.ago, status: "finished", result: "6-4 6-4", active: true))

    assert_equal match, FeaturedMatch.banner.first
  end

  test "banner ignores deactivated matches" do
    match = FeaturedMatch.create!(valid_attributes(starts_at: 1.hour.ago, active: false))

    assert_not_includes FeaturedMatch.banner, match
  end

  test "activating a match deactivates other active matches" do
    first = FeaturedMatch.create!(valid_attributes(active: true))
    second = FeaturedMatch.create!(valid_attributes(player_left_name: "Second", active: true))

    assert_not first.reload.active?
    assert second.reload.active?
  end

  test "database enforces only one active match" do
    FeaturedMatch.create!(valid_attributes(active: true))
    second = FeaturedMatch.create!(valid_attributes(player_left_name: "Second", active: false))

    assert_raises(ActiveRecord::RecordNotUnique) do
      second.update_column(:active, true)
    end
  end

  test "seo title and description describe the match" do
    match = FeaturedMatch.new(valid_attributes(starts_at: 2.days.from_now))

    assert_equal "M. Andreeva vs M. Kostyuk · Roland Garros Final", match.seo_title
    assert_includes match.seo_description, "Live on"
    assert_nil match.og_image_url
  end

  test "generates slug and uses it as param" do
    match = FeaturedMatch.create!(valid_attributes)

    assert_equal "roland-garros-final-#{match.starts_at.year}-m-andreeva-m-kostyuk", match.slug
    assert_equal match.slug, match.to_param
  end

  test "keeps the game link while the game still describes the event" do
    game = Game.create!(user: users(:one), court: courts(:one), date: Date.yesterday, recurring: false)
    match = build_match(game: game, starts_at: Time.zone.yesterday.change(hour: 17))

    assert match.game_page_relevant?
  end

  test "drops the game link once a recurring game rolls over to the next week" do
    game = Game.create!(user: users(:one), court: courts(:one), date: 3.weeks.ago.to_date, recurring: true)
    # Пятничный ResetParticipationsJob уже перевёл игру на ближайшее вхождение.
    game.mark_participations_reset!(game.next_date)
    starts_at = (game.next_date - 2.weeks).in_time_zone.change(hour: 17)

    match = build_match(game: game.reload, starts_at: starts_at)

    assert_not match.game_page_relevant?
  end

  test "drops the game link when the game is deleted" do
    game = Game.create!(user: users(:one), court: courts(:one), date: Date.yesterday, recurring: false)
    match = build_match(game: game, starts_at: Time.zone.yesterday.change(hour: 17))
    match.save!

    game.destroy

    assert_nil match.reload.game_id
    assert_not match.game_page_relevant?
  end

  test "an event without a game has no link at all" do
    assert_not build_match(game: nil, starts_at: 1.day.from_now).game_page_relevant?
  end

  test "validates slug format" do
    match = FeaturedMatch.new(valid_attributes(slug: "Bad Slug"))

    assert_not match.valid?
    assert_includes match.errors[:slug], "is invalid"
  end

  test "finished seo description includes result" do
    match = FeaturedMatch.new(valid_attributes(status: "finished", result: "M. Andreeva won 6-4, 6-4"))

    assert_includes match.seo_description, "Final result"
    assert_includes match.seo_description, "6-4"
  end

  test "event status schema maps status" do
    match = FeaturedMatch.new(valid_attributes(status: "live"))

    assert_equal "https://schema.org/EventScheduled", match.event_status_schema
  end

  test "event status schema only returns valid schema.org event statuses" do
    valid_schema_statuses = %w[
      https://schema.org/EventScheduled
      https://schema.org/EventCancelled
      https://schema.org/EventMovedOnline
      https://schema.org/EventPostponed
      https://schema.org/EventRescheduled
    ]

    FeaturedMatch::STATUSES.each do |status|
      match = FeaturedMatch.new(valid_attributes(status: status))

      assert_includes valid_schema_statuses, match.event_status_schema
    end
  end

  test "court association is optional" do
    match = FeaturedMatch.create!(valid_attributes(court: nil))

    assert_nil match.court
  end

  private

  def valid_attributes(overrides = {})
    {
      tournament_label: "Roland Garros Final",
      player_left_name: "M. Andreeva",
      player_left_flag: "RU",
      player_right_name: "M. Kostyuk",
      player_right_flag: "UA",
      starts_at: 1.day.from_now,
      status: "scheduled",
      active: false
    }.merge(overrides)
  end

  def build_match(game:, starts_at:)
    FeaturedMatch.new(valid_attributes(game: game, starts_at: starts_at))
  end
end
