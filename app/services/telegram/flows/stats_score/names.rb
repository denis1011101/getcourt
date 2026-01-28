module Telegram
  module Flows
    module StatsScore
      module Names
        module_function

        def display_name(user)
          user.name.to_s.strip.presence ||
            user.telegram_username.to_s.strip.presence ||
            user.email.to_s
        end

        def team_names(conv, ids)
          players = Array(conv["players"]).map { |h| [h["id"].to_i, h["name"].to_s] }.to_h
          Array(ids).map { |id| players[id.to_i] || "##{id}" }.join(" + ")
        end
      end
    end
  end
end
