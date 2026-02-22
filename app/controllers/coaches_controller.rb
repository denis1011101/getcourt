class CoachesController < ApplicationController
  skip_before_action :authenticate_user!, only: :index

  def index
    scope = User.where(coach: true)
    user_city = current_user&.city_name.to_s.strip.downcase.presence

    @coaches =
      if user_city
        order_sql = ActiveRecord::Base.sanitize_sql_array(
          [ "CASE WHEN LOWER(city_name) = ? THEN 0 ELSE 1 END, name ASC", user_city ]
        )
        scope.order(
          Arel.sql(order_sql)
        )
      else
        scope.order(name: :asc)
      end
  end
end
