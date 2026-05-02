# Preview all emails at http://localhost:3000/rails/mailers/user_mailer
class UserMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/user_mailer/login_code_email
  def login_code_email
    user = User.new(email: "preview@example.com", telegram_locale: I18n.locale.to_s)
    UserMailer.login_code_email(user, "1234")
  end
end
