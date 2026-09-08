require "test_helper"

class OutreachContactTest < ActiveSupport::TestCase
  test "import reads plain addresses and `email,name` lines, skipping repeats and junk" do
    added = OutreachContact.import([
      "One@Example.org \n",
      "two@example.org,Ace Club\n",
      "one@example.org\n",
      "not-an-email\n",
      "\n"
    ])

    assert_equal 2, added
    assert_equal %w[one@example.org two@example.org], OutreachContact.order(:id).pluck(:email)
    assert_equal "Ace Club", OutreachContact.find_by(email: "two@example.org").name
  end

  test "pending leaves out sent, unsubscribed, reserved and hopeless contacts" do
    waiting = OutreachContact.create!(email: "waiting@example.org")
    OutreachContact.create!(email: "sent@example.org", sent_at: Time.current)
    OutreachContact.create!(email: "gone@example.org", unsubscribed_at: Time.current)
    OutreachContact.create!(email: "taken@example.org", reserved_at: Time.current)
    OutreachContact.create!(email: "broken@example.org", attempts: OutreachContact::MAX_ATTEMPTS)

    assert_equal [ waiting ], OutreachContact.pending.to_a
  end

  test "a reservation left by a crashed run frees up after the TTL" do
    contact = OutreachContact.create!(email: "stuck@example.org", reserved_at: OutreachContact::RESERVATION_TTL.ago - 1.minute)

    assert_equal [ contact ], OutreachContact.pending.to_a
  end

  test "the daily limit counts letters sent today and reservations still in flight" do
    OutreachContact.create!(email: "sent@example.org", sent_at: Time.current)
    OutreachContact.create!(email: "taken@example.org", reserved_at: Time.current)
    OutreachContact.create!(email: "yesterday@example.org", sent_at: 1.day.ago)
    OutreachContact.create!(email: "stuck@example.org", reserved_at: OutreachContact::RESERVATION_TTL.ago - 1.minute)

    assert_equal 2, OutreachContact.daily_limit_taken.count
  end

  test "a reservation taken before midnight still counts after it" do
    OutreachContact.create!(email: "taken@example.org", reserved_at: Time.zone.parse("2026-09-09 23:59"))

    travel_to Time.zone.parse("2026-09-10 00:01") do
      assert_equal 1, OutreachContact.daily_limit_taken.count
    end
  end
end
