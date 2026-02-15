require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  test "login_code_email" do
    user = User.new(email: "to@example.org")
    mail = UserMailer.login_code_email(user, "1234")

    assert_equal "Your GetCourt login code", mail.subject
    assert_equal [ "to@example.org" ], mail.to
    assert_equal [ "from@example.com" ], mail.from
    assert_match "User#login_code_email", mail.body.encoded
  end
end
