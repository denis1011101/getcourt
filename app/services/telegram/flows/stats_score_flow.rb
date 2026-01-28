module Telegram
  module Flows
    class StatsScoreFlow
      class << self
        def handle_callback(callback_query)
          Telegram::Flows::StatsScore::CallbackRouter.call(callback_query)
        end

        def handle_message(message)
          Telegram::Flows::StatsScore::MessageHandler.call(message)
        end
      end
    end
  end
end
