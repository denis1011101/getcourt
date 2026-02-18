module Telegram
  module Flows
    class GamesFlow
      class << self
        def handle_callback(callback)
          cb = Telegram::Helpers::CallbackData.parse(callback)
          Rails.logger.debug "[Telegram::Flows::GamesFlow] enter handle_callback data=#{cb.data.inspect}"
          poller = Telegram::Poller.new

          return true if Telegram::Flows::Games::InviteFlow.handle_callback(callback) rescue false
          return true if Telegram::Flows::Games::ParticipantsManageFlow.handle_callback(callback) rescue false

          case cb.data
          when /\Agame:show:(\d+):(\d+)\z/
            gid = $1.to_i
            page = $2.to_i
            poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil
            begin
              Telegram::Handlers::GamesHandler.show_game(cb.chat_id, gid, page, message_id: cb.message_id)
            rescue => e
               Rails.logger.error "[Telegram::Flows::GamesFlow] show_game error: #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}"
               raise
            end
            nil

          when /\Agame:players:(\d+):(\d+)\z/
            gid = $1.to_i
            page = $2.to_i
            poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil
            Telegram::Handlers::GamesHandler.show_players(cb.chat_id, gid, page, message_id: cb.message_id) rescue nil
            nil

          when /\Agame:invite:/, /\Agame:invite_decline:/
            handled = Telegram::Flows::Games::InviteFlow.handle_callback(callback) rescue false
            handled

          when /\Agame:prebook/, /\Aprebook:/
            Rails.logger.debug "[Telegram::Flows::GamesFlow] delegating to Games::PrebookFlow data=#{cb.data.inspect}"
            begin
              result = Telegram::Flows::Games::PrebookFlow.handle_callback(callback)
              Rails.logger.debug "[Telegram::Flows::GamesFlow] Games::PrebookFlow returned=#{result.inspect}"
            rescue => e
              Rails.logger.error "[Telegram::Flows::GamesFlow] prebook flow error: #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}"
              result = nil
            end
            result

          when /\Agame:/
            Telegram::Flows::Games::ManageFlow.handle_callback(callback) rescue nil
            nil

          else
            # other actions handled elsewhere
          end
        rescue => e
          Rails.logger.error "[Telegram::Flows::Games::ManageFlow] callback error: #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
          nil
        end
      end
    end
  end
end
