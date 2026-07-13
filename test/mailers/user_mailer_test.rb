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

  test "urgent player search email includes game links and respects web locale" do
    owner = User.create!(email: "mailer_owner@example.com")
    recipient = User.create!(email: "mailer_recipient@example.com", name: "Player", locale: "es")
    court = Court.create!(name: "Central Court", city_name: "Madrid")
    game = Game.create!(
      court: court,
      user: owner,
      date: Date.current + 1.day,
      time: "20:00",
      sport: "Tennis",
      skill_level: "advanced"
    )

    mail = UserMailer.urgent_player_search(recipient, game)
    body = mail.parts.map(&:decoded).join

    assert_equal "Se necesitan jugadores para un partido en Madrid", mail.subject
    assert_equal [ recipient.email ], mail.to
    assert_includes body, Rails.application.routes.url_helpers.game_url(game, host: "example.com")
    assert_includes body, Rails.application.routes.url_helpers.notifications_account_url(host: "example.com")
    assert_includes body, "Central Court"
    assert_includes body, "Usuario de GetCourt ##{owner.id}"
    assert_not_includes body, owner.email
  ensure
    game&.destroy
    court&.destroy
    recipient&.destroy
    owner&.destroy
  end
end
