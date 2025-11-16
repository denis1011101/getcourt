class SearchesController < ApplicationController
  def index
    location = params[:location]&.strip
    if location.blank?
      @courts = Court.none
    else
      loc = Court.parse_location(location)
      if loc
        @courts = Court.near("#{loc[0]},#{loc[1]}", 10)
      else
        @courts = Court.where("LOWER(name) LIKE LOWER(?)", "%#{location}%")
      end
    end
  end
end
