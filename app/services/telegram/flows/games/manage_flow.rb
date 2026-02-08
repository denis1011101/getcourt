module Telegram
  module Flows
    module Games
      module ManageFlow
        class << self
          def handle_callback(callback)
            data = (callback["data"] || "").to_s

            case data
            when /\Agame:create\b/
              Telegram::Flows::Games::Manage::CreateFlow.handle_callback(callback)
            when /\Agame:edit\b/
              Telegram::Flows::Games::Manage::EditFlow.handle_callback(callback)
            when /\Agame:join\b/, /\Agame:leave\b/, /\Agame:join_pending\b/
              Telegram::Flows::Games::Manage::JoinFlow.handle_callback(callback)
            when /\Agame:approve_participation:/, /\Agame:reject_participation:/
              Telegram::Flows::Games::Manage::ApproveFlow.handle_callback(callback)
            when /\Agame:delete\b/
              Telegram::Flows::Games::Manage::DeleteFlow.handle_callback(callback)
            else
              Rails.logger.debug "[Telegram::Flows::Games::ManageFlow] unknown action: #{data}"
              nil
            end
          rescue => e
            Rails.logger.error "[Telegram::Flows::Games::ManageFlow] callback error: #{e.class} #{e.message}"
            nil
          end

          # small helper delegates kept for callers that used these methods
          def start_create_game(chat_id, cb_id: nil)
            Telegram::Flows::Games::Manage::CreateFlow.start_create_game(chat_id, cb_id: cb_id)
          rescue => e
            Rails.logger.error "[Telegram::Flows::Games::ManageFlow] start_create_game: #{e.class} #{e.message}"
            nil
          end

          def start_edit_game(chat_id, game_id, cb_id: nil, message_id: nil)
            Telegram::Flows::Games::Manage::EditFlow.start_edit_game(chat_id, game_id, cb_id: cb_id, message_id: message_id)
          rescue => e
            Rails.logger.error "[Telegram::Flows::Games::ManageFlow] start_edit_game: #{e.class} #{e.message}"
            nil
          end

          def delete_game(chat_id, game_id, page = 1, message_id: nil)
            Telegram::Flows::Games::Manage::DeleteFlow.delete_game(chat_id, game_id, page, message_id: message_id)
          rescue => e
            Rails.logger.error "[Telegram::Flows::Games::ManageFlow] delete_game: #{e.class} #{e.message}"
            nil
          end
        end
      end
    end
  end
end
