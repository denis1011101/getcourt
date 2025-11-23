class SessionsController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[new create verify check]

  def new
    # Сохраняем откуда пришли (только если это наш сайт и session[:return_to] ещё не установлен)
    if session[:return_to].blank? && request.referer.present?
      uri = URI.parse(request.referer) rescue nil
      # Проверяем что это наш домен и не сама страница /sign_in
      if uri && (uri.host.nil? || uri.host == request.host) && uri.path != new_session_path
        session[:return_to] = uri.request_uri
      end
    end
    # renders app/views/sessions/new.html.erb
  end

  # POST /sign_in
  # params: email, via (email|telegram)
  def create
    email = params[:email].to_s.strip.downcase
    via = params[:via].to_s.presence || "email"

    if email.blank?
      redirect_to new_session_path, alert: "Email required" and return
    end

    user = User.find_or_create_by(email: email) do |u|
      u.name = email.split("@").first.titleize
    end

    code = user.generate_login_code!(via: via)

    case via
    when "email"
      UserMailer.login_code_email(user, code).deliver_later
    when "telegram"
      unless user.telegram_chat_id.present?
        redirect_to new_session_path, alert: "No Telegram connected for this account" and return
      end
      TelegramNotifier.send_message(user.telegram_chat_id, "Your GetCourt login code: #{code}")
    else
      redirect_to new_session_path, alert: "Unknown delivery method" and return
    end

    redirect_to verify_session_path(email: user.email), notice: "Login code sent via #{via}"
  end

  # GET /sign_in/verify
  def verify
    @email = params[:email]
  end

  # POST /sign_in/verify
  # params: email, code
  def check
    email = params[:email].to_s.strip.downcase
    code = params[:code].to_s.strip

    user = User.find_by(email: email)

    if user && user.valid_login_code?(code)
      user.clear_login_code!
      sign_in(user)
      target = session.delete(:return_to) || root_path
      redirect_to target, notice: "Signed in as #{user.email}"
    else
      flash.now[:alert] = "Invalid or expired code"
      @email = email
      render :verify, status: :unprocessable_entity
    end
  end

  def destroy
    sign_out

    # Редирект на страницу откуда вышли (если это наш сайт) или на главную
    target = root_path
    if request.referer.present?
      uri = URI.parse(request.referer) rescue nil
      if uri && (uri.host.nil? || uri.host == request.host)
        target = uri.request_uri
      end
    end

    redirect_to target, notice: "Signed out"
  end
end
