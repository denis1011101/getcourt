module Telegram
  module Flows
    module StatsScore
      module Actions
        module PromptScore
          module_function

          def call(chat_id:, message_id:, cb_id:, game_id:, invalid:)
            StatsScore::Ui.prompt_score(chat_id:, message_id:, game_id:, cb_id:, invalid:)
          end
        end
      end
    end
  end
end
