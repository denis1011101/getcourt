module Telegram
  module Flows
    module StatsScore
      module CallbackRouter
        module_function

        def call(callback_query)
          cb = Telegram::Helpers::CallbackData.parse(callback_query)
          return if cb.chat_id.blank? || cb.data.blank?

          chat_id = cb.chat_id
          message_id = cb.message_id
          cb_id = cb.cb_id

          case cb.data
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
          cb_id = callback_query["id"] rescue nil
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id) rescue "ru"
          Telegram::Api.answer_callback(cb_id, Telegram::I18n.t(:score_error, locale: locale), show_alert: true) rescue nil
          nil
        end
      end
    end
  end
end
