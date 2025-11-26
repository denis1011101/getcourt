class ApplicationController < ActionController::Base
  # Browser support check (keeps tolerant policy; skips in development and for non-HTML requests).
  before_action :check_browser_support, if: -> { request.format.html? }

  protect_from_forgery with: :exception
  before_action :authenticate_user!

  helper_method :current_user, :user_signed_in?, :sign_in, :sign_out, :geocoding_exceeded?, :can_manage?, :can_remove_participant?

  private

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

    redirect_to new_session_path, alert: "Please sign in or sign up"
  end

  def geocoding_exceeded?
    defined?(Geocoding::Quota) && Geocoding::Quota.exceeded?
  end
end
