class ApplicationController < ActionController::Base
  include Pagy::Method
  # Browser support check (keeps tolerant policy; skips in development and for non-HTML requests).
  before_action :check_browser_support, if: -> { request.format.html? }
  before_action :set_locale_from_subdomain
  before_action :set_suggested_locale

  protect_from_forgery with: :exception
  before_action :authenticate_user!

  helper_method :current_user, :user_signed_in?, :sign_in, :sign_out, :geocoding_exceeded?, :can_manage?, :can_remove_participant?,
                :can_send_training_video?

  private

  def set_locale_from_subdomain
    locale = request.subdomains.first
    I18n.locale = I18n.available_locales.map(&:to_s).include?(locale) ? locale : I18n.default_locale
  end

  def set_suggested_locale
    return unless request.get? && request.format.html?
    return unless request.host == ApplicationHelper::SEO_PRIMARY_HOST
    return if cookies[:preferred_locale].present? || cookies[:locale_banner_dismissed].present?
    return if crawler_request?

    detected_locale = LocaleDetector.call(request, cookies)
    @suggested_locale = detected_locale if detected_locale != I18n.default_locale.to_s
  end

  def crawler_request?
    request.user_agent.to_s.match?(/Googlebot|Bingbot/i)
  end

  def check_browser_support
    # If Browser gem is not available or in development, skip strict checks.
    return if Rails.env.development?
    return unless defined?(Browser)

    browser = Browser.new(request.user_agent)
    allowed = browser.modern? || browser.mobile? || browser.tablet?

    unless allowed
      render plain: "Please use a modern browser.", status: :unsupported_media_type
    end
  rescue => e
    Rails.logger.debug "Browser check skipped: #{e.class} #{e.message}"
  end

  def can_manage?(record)
    AccessControl.can_manage?(current_user, record)
  end

  def can_remove_participant?(game, participation_user)
    AccessControl.can_remove_participant?(current_user, game, participation_user)
  end

  # Рассылку ролика инициирует тот, кто ведёт игру: организатор, админ или
  # принятый тренер. Живёт здесь, а не в GameMediaController, потому что
  # галочку рисует games/_media, а его отдаёт GamesController.
  def can_send_training_video?(game)
    return false unless current_user

    can_manage?(game) || (game.coach_id == current_user.id && game.coach_accepted?)
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id].present?
  end

  def user_signed_in?
    current_user.present?
  end

  def sign_in(user)
    session[:user_id] = user.id
  end

  def sign_out
    session.delete(:user_id)
    @current_user = nil
  end

  def authenticate_user!
    return if user_signed_in?

    # Сохраняем откуда пришли (только GET запросы с нашего домена)
    if request.get? && request.format.html?
      session[:return_to] = request.fullpath
    elsif request.referer.present?
      # для POST попробуем взять referer
      uri = URI.parse(request.referer) rescue nil
      if uri && (uri.host.nil? || uri.host == request.host)
        session[:return_to] = uri.request_uri
      end
    end

    redirect_to new_session_path, alert: "Please sign in or sign up", status: :see_other
  end

  def geocoding_exceeded?
    defined?(Geocoding::Quota) && Geocoding::Quota.exceeded?
  end
end
