module Telegram
  module Flows
    module StatsScore
      module Actions
        module SwapTeams
          module_function

          def call(chat_id:, message_id:, cb_id:, game_id:)
            conv = StatsScore::State.get(chat_id)
            return unless conv.is_a?(Hash) && conv["game_id"].to_i == game_id

            a = Array(conv["team_a_ids"]).map(&:to_i)
            b = Array(conv["team_b_ids"]).map(&:to_i)
            conv["team_a_ids"] = b
            conv["team_b_ids"] = a

            StatsScore::State.set(chat_id, conv.merge("message_id" => message_id))
            StatsScore::Ui.render_setup(chat_id:)
            Telegram::Api.answer_callback(cb_id) rescue nil
          end
        end
      end
    end
  end
end
