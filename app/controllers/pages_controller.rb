class PagesController < ApplicationController
  # public pages
  skip_before_action :authenticate_user!, only: %i[contacts mission partnership tennis_formats_and_rules ntrp_level_guide]

  def contacts
  end

  def mission
  end

  def partnership
  end

  def tennis_formats_and_rules
  end

  def ntrp_level_guide
  end
end
