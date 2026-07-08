module Telegram
  module Flows
    module Games
      module ParticipantsManageFlow
        class << self
          def handle_callback(callback_query)
            data  = (callback_query["data"] || "").to_s
            return false unless data.match?(/\Agame:(manage|remove|removep):/)

            cb_id = callback_query["id"]
            from  = callback_query["from"] || {}
            chat_id = (callback_query.dig("message", "chat", "id") || from["id"]).to_s
            msg_id  = callback_query.dig("message", "message_id") || callback_query["inline_message_id"]

            user = User.find_by(telegram_chat_id: chat_id) rescue nil
            locale = Telegram::I18n.locale_for(user)
            t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

            case data
            when /\Agame:manage:(\d+):(\d+)\z/
              game_id = $1.to_i
              page    = $2.to_i
              game = Game.includes(participations: :user).find_by(id: game_id)

              unless game && user && (user.admin? || game.user_id == user.id)
                Telegram::Api.answer_callback(cb_id, t.(:manage_players_owner_admin_only), show_alert: false) rescue nil
                return true
              end

              Telegram::Api.answer_callback(cb_id, t.(:manage_players_callback), show_alert: false) rescue nil
              show_manage(chat_id, msg_id, game, page, t)
              return true

            when /\Agame:removep:(\d+):(\d+):(\d+)\z/
              game_id = $1.to_i
              participation_id = $2.to_i
              page = $3.to_i

              game = Game.includes(participations: :user).find_by(id: game_id)
              unless game && user && (user.admin? || game.user_id == user.id)
                Telegram::Api.answer_callback(cb_id, t.(:remove_players_owner_admin_only), show_alert: false) rescue nil
                return true
              end

              participation = game.participations.find_by(id: participation_id)
              remove_participation(chat_id, msg_id, cb_id, game, participation, page, t)
              return true

            when /\Agame:remove:(\d+):(\d+):(\d+)\z/
              game_id = $1.to_i
              target_user_id = $2.to_i
              page = $3.to_i

              game = Game.includes(participations: :user).find_by(id: game_id)
              unless game && user && (user.admin? || game.user_id == user.id)
                Telegram::Api.answer_callback(cb_id, t.(:remove_players_owner_admin_only), show_alert: false) rescue nil
                return true
              end

              participation = game.participations.find_by(user_id: target_user_id)
              remove_participation(chat_id, msg_id, cb_id, game, participation, page, t)
              return true
            end

            false
          rescue => e
            Rails.logger.error "[Telegram::Flows::Games::ParticipantsManageFlow] error: #{e.class} #{e.message}"
            false
          end

          private

          def show_manage(chat_id, message_id, game, page, t)
            participants = game.participations.to_a
            others = participants.reject { |participation| participation.user_id == game.user_id }

            text_lines = []
            text_lines << "*#{t.(:manage_players_title, game_id: game.id)}*"
            text_lines << t.(:manage_players_count, count: participants.size)
            text_lines << ""
            if participants.empty?
              text_lines << t.(:manage_players_empty)
            else
              participants.each_with_index do |participation, idx|
                text_lines << "#{idx + 1}. #{target_label(participation, t)}"
              end
            end
            text = text_lines.join("\n")

            buttons = []
            if others.empty?
              buttons << [ { text: t.(:back_to_game), callback_data: "game:show:#{game.id}:#{page}" } ]
            else
              others.each do |participation|
                buttons << [ { text: t.(:manage_players_remove_btn, name: target_label(participation, t)), callback_data: "game:removep:#{game.id}:#{participation.id}:#{page}" } ]
              end
              buttons << [ { text: t.(:back_to_game), callback_data: "game:show:#{game.id}:#{page}" } ]
            end

            Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons) rescue nil
          end

          def target_label(participation, t)
            if participation.respond_to?(:guest?) && participation.guest?
              "#{participation.guest_name} (#{t.(:guest_badge)})"
            else
              u = participation.respond_to?(:user) ? participation.user : participation
              Telegram::Helpers::UserLookup.display_name(u, fallback: u&.id ? "user##{u.id}" : "User")
            end
          end

          def remove_participation(chat_id, message_id, cb_id, game, participation, page, t)
            unless participation
              Telegram::Api.answer_callback(cb_id, t.(:manage_players_not_found), show_alert: false) rescue nil
              show_manage(chat_id, message_id, game, page, t) rescue nil
              return
            end

            if participation.user_id == game.user_id
              Telegram::Api.answer_callback(cb_id, t.(:manage_players_cant_remove_owner), show_alert: false) rescue nil
              show_manage(chat_id, message_id, game, page, t) rescue nil
              return
            end

            target_user = participation.user
            label = target_label(participation, t)
            participation.destroy! rescue nil

            Telegram::Api.answer_callback(cb_id, t.(:manage_players_removed), show_alert: false) rescue nil
            Telegram::Api.send_simple(chat_id, t.(:manage_players_removed_from_game, name: label, game_id: game.id)) rescue nil

            if target_user&.telegram_chat_id.present?
              target_locale = Telegram::I18n.locale_for(target_user)
              target_t = ->(key, **args) { Telegram::I18n.t(key, locale: target_locale, **args) }
              Telegram::Api.send_simple(target_user.telegram_chat_id.to_s, target_t.(:manage_players_you_were_removed, game_id: game.id)) rescue nil
            end

            game = Game.includes(participations: :user).find_by(id: game.id)
            show_manage(chat_id, message_id, game, page, t) if game
          end
        end
      end
    end
  end
end
