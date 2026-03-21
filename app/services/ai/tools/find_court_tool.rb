module Ai
  module Tools
    class FindCourtTool < RubyLLM::Tool
      description "Find approved courts by city"
      param :city, desc: "City name to search courts in", required: false
      param :sport, desc: "Sport filter", required: false

      def initialize(user)
        @user = user
      end

      def execute(city: nil, sport: nil)
        search_city = city.to_s.strip.presence || @user&.city_name.to_s.strip.presence
        return { error: "City is required. Ask the user to set their city in profile or specify a city." } if search_city.blank?

        scope = Court.approved.where("LOWER(city_name) LIKE LOWER(?)", "%#{search_city}%")
        scope = scope.where(sport: sport.to_s.strip) if sport.to_s.strip.present?
        courts = scope.limit(5)

        if courts.empty?
          return {
            city: search_city,
            courts: [],
            message: "No courts found."
          }
        end

        host = ENV.fetch("APP_HOST", ENV.fetch("HOSTNAME", "https://getcourt.co"))
        {
          city: search_city,
          courts: courts.map do |court|
            {
              name: court.name,
              city: court.city_name,
              sport: court.sport.presence || "unknown",
              url: "#{host}/courts/#{court.id}"
            }
          end
        }
      end
    end
  end
end
