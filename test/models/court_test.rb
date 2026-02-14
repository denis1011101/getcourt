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
end
