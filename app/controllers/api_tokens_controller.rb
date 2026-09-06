class ApiTokensController < ApplicationController
  # Код четырёхзначный, и лимит Rack::Attack на подтверждении держится только за
  # адрес: почты в запросе нет, счётчику не за что зацепиться. Поэтому промахи
  # считаем сами и после пятого гасим код — дальше перебирать нечего.
  MAX_CODE_ATTEMPTS = 5
  FAILURE_WINDOW = 15.minutes

  before_action :require_verified_user
  before_action :require_confirmed_ownership, except: %i[send_code confirm]

  def show
    respond_to do |format|
      format.html { redirect_to security_account_path }
      format.json do
        token = current_user.api_tokens.active.first
        token ? render(json: token_json(token)) : render(json: { error: "not_found" }, status: :not_found)
      end
    end
  end

  def create
    token = ApiToken.issue_for(current_user)

    respond_to do |format|
      format.html { redirect_to security_account_path, notice: t("api_tokens.issued") }
      format.json { render json: token_json(token), status: :created }
    end
  end

  def destroy
    current_user.api_tokens.active.find_each(&:revoke!)

    respond_to do |format|
      format.html { redirect_to security_account_path, notice: t("api_tokens.revoked") }
      format.json { head :no_content }
    end
  end

  # Код тот же, что и при входе: он уходит на подтверждённую почту или в
  # привязанный телеграм, то есть туда, куда чужой не заглянет.
  def send_code
    deliver_confirmation_code

    respond_to do |format|
      format.html { redirect_to security_account_path, notice: t("api_tokens.code_sent") }
      format.json { head :accepted }
    end
  end

  def confirm
    unless current_user.valid_login_code?(params[:code].to_s.strip)
      register_failed_confirmation

      respond_to do |format|
        format.html { redirect_to security_account_path, alert: t("api_tokens.code_invalid") }
        format.json { render json: { error: "code_invalid" }, status: :forbidden }
      end
      return
    end

    current_user.clear_login_code!
    Rails.cache.delete(confirmation_failures_key)
    confirm_api_token_ownership!

    respond_to do |format|
      format.html { redirect_to security_account_path, notice: t("api_tokens.confirmed") }
      format.json { head :no_content }
    end
  end

  private

  # Токен выдаём только тому, за кем стоит подтверждённая почта или привязанный
  # телеграм: иначе это раздача доступа кому угодно, и отзывать его будет не у
  # кого — аккаунт заведут заново за минуту.
  def require_verified_user
    return if current_user.verified?

    respond_to do |format|
      format.html { redirect_to new_account_verification_path, alert: t("api_tokens.verification_required") }
      format.json { render json: { error: "verification_required" }, status: :forbidden }
    end
  end

  # Вход в аккаунт кода может и не требовать, а вот выдача долгоживущего ключа —
  # требует: иначе токен достаётся любому, кто знает почту владельца.
  def require_confirmed_ownership
    return if api_token_confirmed?

    respond_to do |format|
      format.html { redirect_to security_account_path, alert: t("api_tokens.confirmation_required") }
      format.json { render json: { error: "confirmation_required" }, status: :forbidden }
    end
  end

  def register_failed_confirmation
    failures = Rails.cache.read(confirmation_failures_key).to_i + 1
    Rails.cache.write(confirmation_failures_key, failures, expires_in: FAILURE_WINDOW)
    current_user.clear_login_code! if failures >= MAX_CODE_ATTEMPTS
  end

  def confirmation_failures_key
    "api_token_confirm_failures:#{current_user.id}"
  end

  def deliver_confirmation_code
    Rails.cache.delete(confirmation_failures_key)

    if current_user.telegram_chat_id.present?
      code = current_user.generate_login_code!(via: "telegram")
      ::Telegram::Notifier.send_message(current_user.telegram_chat_id, "Your GetCourt login code: `#{code}`")
    else
      code = current_user.generate_login_code!(via: "email")
      UserMailer.login_code_email(current_user, code).deliver_later
    end
  end

  def token_json(token)
    {
      token: token.token,
      expires_at: token.expires_at.iso8601,
      last_used_at: token.last_used_at&.iso8601,
      endpoint: "#{ENV.fetch('APP_HOST', 'https://getcourt.co')}/mcp"
    }
  end
end
