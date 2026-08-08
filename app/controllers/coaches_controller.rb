class CoachesController < ApplicationController
  include LocationFilters

  skip_before_action :authenticate_user!, only: :index

  def index
    scope = User.not_merged.where(coach: true).includes(:favorite_courts)
    prepare_location_filters(scope.where.not(city_name: [ nil, "" ]).distinct.pluck(:city_name))

    coaches = scope.order(name: :asc).to_a

    if params[:country].present? && params[:city].blank?
      cities_in_country = cities_for_country(params[:country])
      coaches = coaches.select { |coach| cities_in_country.include?(coach.city_name) }
    elsif params[:city].present?
      coaches = coaches.select { |coach| coach.city_name == params[:city] }
    elsif current_user&.city_name.present?
      user_city = normalized_city(current_user.city_name)
      local, other = coaches.partition { |coach| normalized_city(coach.city_name) == user_city }
      coaches = local + other
    end

    @coaches = coaches
  end
end
