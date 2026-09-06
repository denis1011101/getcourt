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
  def create
    email = params[:email].to_s.strip.downcase
    if email.blank?
      redirect_to new_session_path, alert: "Email required" and return
    end

    user = User.find_or_initialize_by(email: email)
    user.name = email.split("@").first.titleize if user.name.blank?
    if User::WEB_LOCALES.include?(I18n.locale.to_s) && (user.new_record? || user.locale.blank?)
      user.locale = I18n.locale.to_s
    end
    if user.new_record? && User::TELEGRAM_LOCALES.include?(I18n.locale.to_s)
      user.telegram_locale = I18n.locale.to_s
    end

    result = user.save
    Rails.logger.info "[SessionsController#create] save result=#{result.inspect} persisted=#{user.persisted?} new_record=#{user.new_record?} errors=#{user.errors.full_messages.inspect}"

    unless user.persisted?
      redirect_to new_session_path, alert: "Could not create account" and return
    end

    unless user.save
      Rails.logger.warn "[SessionsController#create] user not saved email=#{email.inspect} errors=#{user.errors.full_messages.inspect}"
      redirect_to new_session_path, alert: user.errors.full_messages.to_sentence.presence || "Could not create account" and return
    end

    if user.require_verification?
      case user.preferred_login_via
      when "telegram"
        unless user.telegram_chat_id.present?
          redirect_to new_session_path, alert: "Telegram not connected for this account" and return
        end

        code = user.generate_login_code!(via: "telegram")
        ::Telegram::Notifier.send_message(user.telegram_chat_id, "Your GetCourt login code: `#{code}`")
        redirect_to verify_session_path(email: user.email), notice: "Login code sent via Telegram", status: :see_other and return
      when "email"
        code = user.generate_login_code!(via: "email")
        UserMailer.login_code_email(user, code).deliver_later
        redirect_to verify_session_path(email: user.email), notice: t("sessions.login_code_sent_email"), status: :see_other and return
      end
    end

    sign_in(user)
    Rails.logger.info "[SessionsController#create] signed in user_id=#{user.id} session_user_id=#{session[:user_id].inspect}"

    target = session.delete(:return_to) || root_path
    redirect_to target, notice: "Signed in as #{user.email}", status: :see_other
  end

  def verify
    @email = params[:email]
    @via = User.find_by(email: @email.to_s.strip.downcase)&.preferred_login_via || "email"
  end

  # POST /sign_in/verify
  def check
    email = params[:email].to_s.strip.downcase
    code  = params[:code].to_s.strip
    user  = User.find_by(email: email)

    # Кто подтверждение не включал, тот и здесь входит по одной почте — как на
    # /sign_in. А кто включил, тот проходит код, каким бы способом его ни
    # получил: раньше условие требовало кода только от телеграма, и почтовый
    # метод пускал с любым набором цифр, то есть защита не работала ровно у тех,
    # кто её себе включил.
    if user && !user.require_verification?
      sign_in(user)
      target = session.delete(:return_to) || root_path
      redirect_to target, notice: "Signed in as #{user.email}" and return
    end

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
