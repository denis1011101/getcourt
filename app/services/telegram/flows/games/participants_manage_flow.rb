module Telegram
  module Flows
    module Games
      module ParticipantsManageFlow
        class << self
          def handle_callback(callback_query)
            data  = (callback_query["data"] || "").to_s
            return false unless data.match?(/\Agame:(manage|remove):/)

            cb_id = callback_query["id"]
            from  = callback_query["from"] || {}
            chat_id = (callback_query.dig("message", "chat", "id") || from["id"]).to_s
            msg_id  = callback_query.dig("message", "message_id") || callback_query["inline_message_id"]

            user = User.find_by(telegram_chat_id: chat_id) rescue nil

            case data
            when /\Agame:manage:(\d+):(\d+)\z/
              game_id = $1.to_i
              page    = $2.to_i
              game = Game.includes(participations: :user).find_by(id: game_id)

              unless game && user && (user.admin? || game.user_id == user.id)
                Telegram::Api.answer_callback(cb_id, "Only the owner/admin can manage players", show_alert: false) rescue nil
                return true
              end

              Telegram::Api.answer_callback(cb_id, "Manage players", show_alert: false) rescue nil
              show_manage(chat_id, msg_id, game, page)
              return true

            when /\Agame:remove:(\d+):(\d+):(\d+)\z/
              game_id = $1.to_i
              target_user_id = $2.to_i
              page = $3.to_i

              game = Game.includes(participations: :user).find_by(id: game_id)
              unless game && user && (user.admin? || game.user_id == user.id)
                Telegram::Api.answer_callback(cb_id, "Only the owner/admin can remove players", show_alert: false) rescue nil
                return true
              end

              if target_user_id == game.user_id
                Telegram::Api.answer_callback(cb_id, "Can't remove the owner", show_alert: false) rescue nil
                show_manage(chat_id, msg_id, game, page) rescue nil
                return true
              end

              participation = game.participations.find_by(user_id: target_user_id)
              unless participation
                Telegram::Api.answer_callback(cb_id, "Player not found in this game", show_alert: false) rescue nil
                show_manage(chat_id, msg_id, game, page) rescue nil
                return true
              end

              target = participation.user
              participation.destroy! rescue nil

              Telegram::Api.answer_callback(cb_id, "Removed", show_alert: false) rescue nil
              Telegram::Api.send_simple(chat_id, "Removed #{target_label(target)} from game ##{game.id}.") rescue nil

              if target&.telegram_chat_id.present?
                Telegram::Api.send_simple(target.telegram_chat_id.to_s, "You were removed from game ##{game.id}.") rescue nil
              end

              # refresh view
              game = Game.includes(participations: :user).find_by(id: game_id)
              show_manage(chat_id, msg_id, game, page) if game
              return true
            end

            false
          rescue => e
            Rails.logger.error "[Telegram::Flows::Games::ParticipantsManageFlow] error: #{e.class} #{e.message}"
            false
          end

          private

          def show_manage(chat_id, message_id, game, page)
            participants = game.participations.map(&:user).compact
            others = participants.reject { |u| u.id == game.user_id }

            text_lines = []
            text_lines << "*Manage players — game ##{game.id}*"
            text_lines << "Participants: #{participants.size}"
            text_lines << ""
            if participants.empty?
              text_lines << "No participants."
            else
              participants.each_with_index do |u, idx|
                text_lines << "#{idx + 1}. #{target_label(u)}"
              end
            end
            text = text_lines.join("\n")

            buttons = []
            if others.empty?
              buttons << [{ text: "Back to game", callback_data: "game:show:#{game.id}:#{page}" }]
            else
              others.each do |u|
                buttons << [{ text: "Remove #{target_label(u)}", callback_data: "game:remove:#{game.id}:#{u.id}:#{page}" }]
              end
              buttons << [{ text: "Back to game", callback_data: "game:show:#{game.id}:#{page}" }]
            end

            Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons) rescue nil
          end

          def target_label(u)
            return "User" unless u
            if u.respond_to?(:telegram_username) && u.telegram_username.present?
              "@#{u.telegram_username}"
            elsif u.respond_to?(:username) && u.username.present?
              "@#{u.username}"
            elsif u.respond_to?(:name) && u.name.present?
              u.name.to_s
            elsif u.respond_to?(:email) && u.email.present?
              u.email.to_s
            else
              "user##{u.id}"
            end
          end
        end
      end
    end
  end
end
