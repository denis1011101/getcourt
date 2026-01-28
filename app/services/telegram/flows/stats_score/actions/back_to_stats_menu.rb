module Telegram
  module Flows
    module StatsScore
      module Actions
        module BackToStatsMenu
          module_function

          def call(chat_id:, message_id:, cb_id:, game_id:)
            conv = StatsScore::State.get(chat_id)
            fields, page = StatsScore::State.fields_and_page_from(conv)

            StatsScore::State.set(
              chat_id,
              {
                "flow" => "game_stats_menu",
                "game_id" => game_id,
                "page" => page,
                "message_id" => message_id || (conv.is_a?(Hash) ? conv["message_id"] : nil),
                "fields" => fields
              }
            )

            Telegram::Flows::StatsFlow.render_menu_for(chat_id)
            Telegram::Api.answer_callback(cb_id) rescue nil if cb_id
          end
        end
      end
    end
  end
end
