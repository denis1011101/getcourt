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
    FeaturedMatch.create!(valid_attributes(starts_at: 1.hour.ago, active: false))

    assert_nil FeaturedMatch.banner.first
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
end
