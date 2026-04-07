module Ai
  module Tools
    class FindOpponentTool < RubyLLM::Tool
      description "Find tennis opponents in the user's city"
      param :city, desc: "City name to search in", required: false
      param :skill_level, desc: "Skill level filter", required: false

      def initialize(user)
        @user = user
      end

      def execute(city: nil, skill_level: nil)
        search_city = city.to_s.strip.presence || @user&.city_name.to_s.strip.presence
        return { error: "City is required. Ask the user to set their city in profile or specify a city." } if search_city.blank?

        scope = User.where("LOWER(city_name) LIKE LOWER(?)", "%#{search_city}%")
                    .where(coach: [ false, nil ])
                    .where.not(id: @user&.id)
        scope = scope.where(skill_level: skill_level.to_s.strip) if skill_level.to_s.strip.present?
        users = scope.limit(5)

        if users.empty?
          return {
            city: search_city,
            opponents: [],
            message: "No opponents found."
          }
        end

        {
          city: search_city,
          opponents: users.map do |user|
            s = PlayerStatistic.summary_for(user)
            {
              name: Telegram::Helpers::UserLookup.display_name(user, fallback: "User ##{user.id}"),
              skill: user.skill_level.presence || "unknown",
              city: user.city_name,
              favorite_courts: user.favorite_courts.map(&:name),
              games: s[:games],
              wins: s[:wins],
              win_pct: s[:win_pct]
            }
          end
        }
      end
    end
  end
end
