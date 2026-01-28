module Telegram
  module Flows
    module StatsScore
      module Actions
        module Reset
          module_function

          def call(chat_id:, message_id:, cb_id:, game_id:)
            conv = StatsScore::State.get(chat_id)
            return unless conv.is_a?(Hash) && conv["game_id"].to_i == game_id

            conv["flow"] = "game_stats_score_setup"
            conv["message_id"] = message_id if message_id.present?
            conv["picked_ids"] = []
            conv["team_a_ids"] = []
            conv["team_b_ids"] = []

            StatsScore::State.set(chat_id, conv)
            StatsScore::Ui.render_setup(chat_id:)
            Telegram::Api.answer_callback(cb_id) rescue nil
          end
        end
      end
    end
  end
end
