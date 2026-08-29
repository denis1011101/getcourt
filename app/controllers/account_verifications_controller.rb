class AccountVerificationsController < ApplicationController
  before_action :redirect_verified_user

  def new
    remember_return_to
  end

  # Отправляем одноразовый код на почту аккаунта — тот же, что и при входе.
  def create
    code = current_user.generate_login_code!(via: "email")
    UserMailer.login_code_email(current_user, code).deliver_later
    redirect_to new_account_verification_path, notice: t("account_verifications.code_sent", email: current_user.email)
  end

  def update
    if current_user.valid_login_code?(params[:code])
      current_user.verify_email!
      current_user.clear_login_code!
      redirect_to session.delete(:verification_return_to) || security_account_path, notice: t("account_verifications.verified")
    else
      flash.now[:alert] = t("account_verifications.invalid_code")
      render :new, status: :unprocessable_entity
    end
  end

  private

  def redirect_verified_user
    redirect_to security_account_path, notice: t("account_verifications.already_verified") if current_user.verified?
  end

  # Со страницы корта человек должен вернуться к своим звёздам, а не в кабинет.
  def remember_return_to
    return if session[:verification_return_to].present?

    uri = URI.parse(request.referer.to_s) rescue nil
    if uri && (uri.host.nil? || uri.host == request.host) && uri.path != new_account_verification_path
      session[:verification_return_to] = uri.request_uri
    end
  end
end
