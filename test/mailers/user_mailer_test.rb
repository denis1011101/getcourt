require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  test "login_code_email renders code and respects user locale (en)" do
    user = User.new(email: "to@example.org", telegram_locale: "en")
    mail = UserMailer.login_code_email(user, "1234")

    assert_equal "Your GetCourt login code", mail.subject
    assert_equal [ "to@example.org" ], mail.to
    assert_equal [ "hello@getcourt.co" ], mail.from
    body = mail.parts.map(&:decoded).join
    assert_match "1234", body
    assert_match "10 minutes", body
  end

  test "login_code_email uses ru subject for ru locale" do
    user = User.new(email: "to@example.org", telegram_locale: "ru")
    mail = UserMailer.login_code_email(user, "9999")

    assert_equal "Код входа в GetCourt", mail.subject
    body = mail.parts.map(&:decoded).join
    assert_match "9999", body
    assert_match "10 минут", body
  end
end
