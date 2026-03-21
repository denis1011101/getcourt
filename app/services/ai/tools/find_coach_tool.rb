module Ai
  module Tools
    class FindCoachTool < RubyLLM::Tool
      description "Find coaches by city"
      param :city, desc: "City name to search coaches in", required: false

      def initialize(user)
        @user = user
      end

      def execute(city: nil)
        search_city = city.to_s.strip.presence || @user&.city_name.to_s.strip.presence
        return { error: "City is required. Ask the user to set their city in profile or specify a city." } if search_city.blank?

        coaches = User.where(coach: true)
                      .where("LOWER(city_name) LIKE LOWER(?)", "%#{search_city}%")
                      .where.not(id: @user&.id)
                      .limit(5)

        if coaches.empty?
          return {
            city: search_city,
            coaches: [],
            message: "No coaches found."
          }
        end

        {
          city: search_city,
          coaches: coaches.map do |coach|
            {
              name: Telegram::Helpers::UserLookup.display_name(coach, fallback: "User ##{coach.id}"),
              city: coach.city_name,
              bio: coach.about_me.presence
            }
          end
        }
      end
    end
  end
end
