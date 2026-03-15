require "test_helper"

class CourtTest < ActiveSupport::TestCase
  test "is invalid without name" do
    court = Court.new(name: nil)

    assert_not court.valid?
    assert_includes court.errors[:name], "can't be blank"
  end

  test "approved scope returns only approved courts" do
    courts(:one).update!(moderation_status: "approved")
    courts(:two).update!(moderation_status: "pending")

    assert_includes Court.approved, courts(:one)
    assert_not_includes Court.approved, courts(:two)
  end

  test "formatted_contact builds label and value" do
    court = courts(:one)
    court.update!(contact_type: "telegram", contact_value: "@getcourt")

    assert_equal "Telegram", court.contact_label
    assert_equal "Telegram: @getcourt", court.formatted_contact
  end

  test "contact_links builds hrefs for multiple contacts" do
    court = Court.new(
      contact_type: "telegram",
      contact_value: "telegram: @getcourt\nwebsite: getcourt.co\nother: Front desk"
    )

    assert_equal [
      "https://t.me/getcourt",
      "https://getcourt.co",
      nil
    ], court.contact_links.map { |contact| contact[:href] }
    assert_equal [
      "Telegram: @getcourt",
      "Website: getcourt.co",
      "Other: Front desk"
    ], court.contact_links.map { |contact| contact[:formatted] }
  end

  test "contact_entries_for_form preserves parsed contacts and pads blanks" do
    court = Court.new(
      contact_type: "telegram",
      contact_value: "telegram: @getcourt\nviber: +79990001122"
    )

    assert_equal [
      { "contact_type" => "telegram", "contact_value" => "@getcourt" },
      { "contact_type" => "viber", "contact_value" => "+79990001122" },
      { "contact_type" => nil, "contact_value" => nil }
    ], court.contact_entries_for_form(3)
  end
end
