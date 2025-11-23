class TennisLifeController < ApplicationController
  skip_before_action :authenticate_user!, only: [:index]

  def index
    # view will provide SEO content_for
  end
end
