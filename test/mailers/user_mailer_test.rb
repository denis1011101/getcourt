require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  test "login_code_email" do
    mail = UserMailer.login_code_email
    assert_equal "Login code email", mail.subject
    assert_equal [ "to@example.org" ], mail.to
    assert_equal [ "from@example.com" ], mail.from
    assert_match "Hi", mail.body.encoded
  end
end
