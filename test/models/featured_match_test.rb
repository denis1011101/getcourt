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
    match = FeaturedMatch.new(valid_attributes(starts_at: Time.zone.local(2026, 6, 8, 15, 0, 0)))

    assert_equal "M. Andreeva vs M. Kostyuk · Roland Garros Final", match.seo_title
    assert_includes match.seo_description, "Live on"
    assert_nil match.og_image_url
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
      active: false
    }.merge(overrides)
  end
end
