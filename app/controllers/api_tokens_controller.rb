class ApiTokensController < ApplicationController
  before_action :require_verified_user

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

  def token_json(token)
    {
      token: token.token,
      expires_at: token.expires_at.iso8601,
      last_used_at: token.last_used_at&.iso8601,
      endpoint: "#{ENV.fetch('APP_HOST', 'https://getcourt.co')}/mcp"
    }
  end
end
