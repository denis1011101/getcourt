class EventsController < ApplicationController
  skip_before_action :authenticate_user!, only: :show

  def show
    @featured_match = FeaturedMatch.find_by!(slug: params[:id])
    @wallchart_event = helpers.wallchart_final?(@featured_match)
    @wallchart_predictions_open = @wallchart_event && helpers.wallchart_banner_active? && @featured_match.starts_at.future?

    track_wallchart_event_view if @wallchart_event && !prefetch_request?
  end

  private
    def track_wallchart_event_view
      ahoy.track "wallchart_event_viewed",
        campaign: ApplicationHelper::WALLCHART_CAMPAIGN,
        event_slug: @featured_match.slug,
        locale: I18n.locale
    end

    # Turbo hover-prefetch (via <link rel="prefetch">) and browser speculation
    # send this header; those requests must not count as event views.
    def prefetch_request?
      "#{request.headers['Sec-Purpose']} #{request.headers['X-Sec-Purpose']}".include?("prefetch")
    end
end
