class LocaleController < ApplicationController
  skip_before_action :authenticate_user!

  def update
    locale = params[:locale].to_s
    return head :bad_request unless ApplicationHelper::SEO_INDEXABLE_LOCALES.include?(locale)

    cookies[:preferred_locale] = shared_cookie_options(
      value: locale,
      expires: 1.year.from_now,
      httponly: true
    )

    redirect_to "https://#{host_for(locale)}#{safe_return_path}", allow_other_host: true
  end

  def dismiss_banner
    cookies[:locale_banner_dismissed] = shared_cookie_options(
      value: "1",
      expires: 1.week.from_now,
      httponly: true
    )

    redirect_to safe_return_path
  end

  private

  def host_for(locale)
    ApplicationHelper.host_for_locale(locale)
  end

  def safe_return_path
    path = params[:return_to].to_s
    return "/" if path.blank?
    return "/" unless path.start_with?("/") && !path.start_with?("//")
    return "/" if path.match?(/\Ahttps?:/i)

    path
  end

  def shared_cookie_options(value:, expires:, httponly:)
    options = {
      value: value,
      expires: expires,
      httponly: httponly,
      same_site: :lax
    }
    options[:domain] = :all if getcourt_host?
    options[:secure] = true if request.ssl? || Rails.env.production?
    options
  end

  def getcourt_host?
    request.host == ApplicationHelper::SEO_PRIMARY_HOST || request.host.end_with?(".getcourt.co")
  end
end
