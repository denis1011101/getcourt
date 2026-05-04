class EventsController < ApplicationController
  skip_before_action :authenticate_user!, only: :show

  def show
    @featured_match = FeaturedMatch.find_by!(slug: params[:id])
  end
end
