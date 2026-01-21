class PagesController < ApplicationController
  # public pages
  skip_before_action :authenticate_user!, only: %i[contacts mission]

  def contacts
  end

  def mission
  end
end
