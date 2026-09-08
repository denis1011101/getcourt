require "test_helper"

class OutreachMailerTest < ActionMailer::TestCase
  test "court booking pitch offers free booking during the test and links the partnership page" do
    contact = OutreachContact.new(email: "club@example.org", name: "Ace Club")

    mail = OutreachMailer.court_booking_pitch(contact)

    assert_equal "Online booking for your club on GetCourt", mail.subject
    assert_equal [ "club@example.org" ], mail.to
    assert_equal [ "hello@getcourt.co" ], mail.from
    body = mail.parts.map(&:decoded).join
    assert_match "I'm Denis, the creator of GetCourt", body
    assert_match "a free trial of online court booking", body
    assert_match "http://example.com/partnership", body
  end

  test "every letter says how to stop them" do
    mail = OutreachMailer.court_booking_pitch(OutreachContact.new(email: "club@example.org"))

    assert_equal "<#{OutreachMailer::UNSUBSCRIBE_MAILTO}>", mail["List-Unsubscribe"].to_s
    assert_match "would rather not hear from me again", mail.parts.map(&:decoded).join
  end

  test "letter stays English even when the app runs in another locale" do
    mail = I18n.with_locale(:ru) { OutreachMailer.court_booking_pitch(OutreachContact.new(email: "club@example.org")) }

    assert_equal "Online booking for your club on GetCourt", mail.subject
  end
end
