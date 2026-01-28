module Telegram
  module Flows
    module StatsScore
      module CallbackRouter
        module_function

        def call(callback_query)
          data = (callback_query["data"] || "").to_s
          cb_id = callback_query["id"]
          from = callback_query["from"] || {}
          chat_id = (callback_query.dig("message", "chat", "id") || from["id"]).to_s
          message_id = callback_query.dig("message", "message_id") || callback_query["inline_message_id"]
          return if chat_id.blank? || data.blank?

          case data
          when /\Atg_score:(\d+)\z/
            Actions::Start.call(chat_id:, message_id:, cb_id:, game_id: Regexp.last_match(1).to_i)
          when /\Atg_score_pick:(\d+):(\d+)\z/
            Actions::PickPlayer.call(chat_id:, message_id:, cb_id:, game_id: Regexp.last_match(1).to_i, user_id: Regexp.last_match(2).to_i)
          when /\Atg_score_swap:(\d+)\z/
            Actions::SwapTeams.call(chat_id:, message_id:, cb_id:, game_id: Regexp.last_match(1).to_i)
          when /\Atg_score_reset:(\d+)\z/
            Actions::Reset.call(chat_id:, message_id:, cb_id:, game_id: Regexp.last_match(1).to_i)
          when /\Atg_score_enter:(\d+)\z/
            Actions::PromptScore.call(chat_id:, message_id:, cb_id:, game_id: Regexp.last_match(1).to_i, invalid: false)
          when /\Atg_score_cancel:(\d+)\z/
            Actions::BackToStatsMenu.call(chat_id:, message_id:, cb_id:, game_id: Regexp.last_match(1).to_i)
          end

          nil
        rescue => e
          Rails.logger.error "[Telegram::Flows::StatsScore::CallbackRouter] error: #{e.class}: #{e.message}"
          Telegram::Api.answer_callback(cb_id, "Error.", show_alert: true) rescue nil
          nil
        end
      end
    end
  end
end
