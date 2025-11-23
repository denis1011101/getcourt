class UserMailer < ApplicationMailer
  def login_code_email(user, code)
    @user = user
    @code = code
    mail(to: user.email, subject: "Your GetCourt login code")
  end
end
