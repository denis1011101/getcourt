# Токен живёт полгода, работает вне браузера и переживает выход из сессии,
# поэтому и показ, и выпуск, и отзыв требуют подтвердить владение аккаунтом
# кодом в текущей сессии — даже если сам вход кода не требовал.
module ApiTokenConfirmation
  extend ActiveSupport::Concern

  CONFIRMATION_TTL = 15.minutes
  SESSION_KEY = :api_token_confirmed_at

  included do
    helper_method :api_token_confirmed?
  end

  def api_token_confirmed?
    confirmed_at = session[SESSION_KEY]
    confirmed_at.present? && Time.zone.at(confirmed_at.to_i) > CONFIRMATION_TTL.ago
  end

  def confirm_api_token_ownership!
    session[SESSION_KEY] = Time.current.to_i
  end

  def forget_api_token_confirmation!
    session.delete(SESSION_KEY)
  end
end
