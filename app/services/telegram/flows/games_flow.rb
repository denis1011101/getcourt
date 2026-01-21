module Telegram
  module Flows
    class GamesFlow
      class << self
        def handle_callback(callback)
          data = (callback["data"] || "").to_s
          Rails.logger.debug "[Telegram::Flows::GamesFlow] enter handle_callback data=#{data.inspect}"
          data = (callback["data"] || "").to_s
          cb_id = callback["id"]
          from = callback["from"] || {}
          chat_id = (callback.dig("message","chat","id") || from["id"]).to_s
          message_id = callback.dig("message","message_id")
          poller = Telegram::Poller.new

          return true if Telegram::Flows::Games::InviteFlow.handle_callback(callback) rescue false
          return true if Telegram::Flows::Games::ParticipantsManageFlow.handle_callback(callback) rescue false

          case data
          when /\Agame:show:(\d+):(\d+)\z/
            gid = $1.to_i
            page = $2.to_i
            poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
            begin
              Telegram::Handlers::GamesHandler.show_game(chat_id, gid, page, message_id: message_id)
            rescue => e
               Rails.logger.error "[Telegram::Flows::GamesFlow] show_game error: #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}"
               raise
            end
            return

          when /\Agame:invite:/, /\Agame:invite_decline:/
            handled = Telegram::Flows::Games::InviteFlow.handle_callback(callback) rescue false
            return handled

          when /\Agame:prebook/ , /\Aprebook:/
            Rails.logger.debug "[Telegram::Flows::GamesFlow] delegating to Games::PrebookFlow data=#{data.inspect}"
            begin
              result = Telegram::Flows::Games::PrebookFlow.handle_callback(callback)
              Rails.logger.debug "[Telegram::Flows::GamesFlow] Games::PrebookFlow returned=#{result.inspect}"
            rescue => e
              Rails.logger.error "[Telegram::Flows::GamesFlow] prebook flow error: #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}"
              result = nil
            end
            return result

          when /\Agame:/
            Telegram::Flows::Games::ManageFlow.handle_callback(callback) rescue nil
            return

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
