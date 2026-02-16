class GeocodingController < ApplicationController
  before_action :authorize_admin!, only: %i[reset]
  skip_before_action :authenticate_user!, only: %i[status reset_form]

  def frame_response
    content = render_to_string(partial: "geocoding/status")
    render html: view_context.turbo_frame_tag("geocoding-status") { content.html_safe }
  end

  def reset_form
    render :reset
  end

   def status
    @current  = ::Geocoding::Quota.current
    @limit    = ::Geocoding::Quota::DAILY_LIMIT
    @exceeded = ::Geocoding::Quota.exceeded?
    frame_response
   end

  def reset
    Rails.cache.delete(::Geocoding::Quota.cache_key)
    @current  = ::Geocoding::Quota.current
    @limit    = ::Geocoding::Quota::DAILY_LIMIT
    @exceeded = ::Geocoding::Quota.exceeded?

    respond_to do |format|
      format.html { redirect_back fallback_location: root_path, notice: "Geocoding quota reset" }
      format.turbo_stream {
        render turbo_stream: turbo_stream.replace("geocoding-status", partial: "geocoding/status")
      }
    end

    if turbo_frame_request?
      frame_response
    else
      redirect_back fallback_location: root_path, notice: "Geocoding quota reset"
    end
  end

  private

  def authorize_admin!
    return if Rails.env.development?
    token = request.headers["X-ADMIN-TOKEN"] || params[:token]
    expected = ENV["ADMIN_TOKEN"].to_s
    unless token.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected)
      head :unauthorized
    end
  end
end
