class UserMailer < ApplicationMailer
  def login_code_email(user, code)
    @user = user
    @code = code
    locale = user.telegram_locale.presence || I18n.default_locale
    I18n.with_locale(locale) do
      mail(to: user.email, subject: t("user_mailer.login_code_email.subject"))
    end
  end
end
