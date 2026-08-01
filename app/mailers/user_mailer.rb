class UserMailer < ApplicationMailer
  def login_code_email(user, code)
    @user = user
    @code = code
    locale = user.telegram_locale.presence || I18n.default_locale
    I18n.with_locale(locale) do
      mail(to: user.email, subject: t("user_mailer.login_code_email.subject"))
    end
  end

  def urgent_player_search(user, game)
    @user = user
    @game = game
    @game_url = game_url(game)
    @notifications_url = notifications_account_url
    locale = user.locale.to_s.presence_in(User::WEB_LOCALES) || I18n.default_locale

    I18n.with_locale(locale) do
      @owner = game.user.name.presence || t("user_mailer.urgent_player_search.organizer_fallback", id: game.user.id)
      @date = l((game.next_date || game.date).to_date, format: :long)
      @time = game.time&.strftime("%H:%M")
      @sport = game.sport.to_s.presence || t("user_mailer.urgent_player_search.any_sport")
      @skill = game.skill_level.to_s.presence&.titleize || t("user_mailer.urgent_player_search.any_level")

      mail(
        to: user.email,
        subject: t("user_mailer.urgent_player_search.subject", city: game.court.city_name)
      )
    end
  end

  def notification(user, subject:, body:, actions: [])
    @body = body
    @actions = actions
    @notifications_url = notifications_account_url
    locale = NotificationDelivery.email_locale(user)

    I18n.with_locale(locale) do
      mail(to: user.email, subject: subject)
    end
  end
end
