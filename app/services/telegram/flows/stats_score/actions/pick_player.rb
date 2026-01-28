module Telegram
  module Flows
    module StatsScore
      module Actions
        module PickPlayer
          module_function

          def call(chat_id:, message_id:, cb_id:, game_id:, user_id:)
            conv = StatsScore::State.get(chat_id)
            return unless conv.is_a?(Hash) && conv["flow"] == "game_stats_score_setup" && conv["game_id"].to_i == game_id

            players = Array(conv["players"]).map { |h| h["id"].to_i }
            return unless players.include?(user_id)

            picked = Array(conv["picked_ids"]).map(&:to_i)
            return if picked.include?(user_id)

            picked << user_id
            conv["picked_ids"] = picked

            if picked.size == 2
              conv["team_a_ids"] = picked
              conv["team_b_ids"] = players - picked
            end

            StatsScore::State.set(chat_id, conv.merge("message_id" => message_id))
            StatsScore::Ui.render_setup(chat_id:)
            Telegram::Api.answer_callback(cb_id) rescue nil
          end
        end
      end
    end
  end
end
