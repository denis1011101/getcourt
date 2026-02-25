module Telegram
  module Flows
    module StatsScore
      module Ui
        module_function

        def render_setup(chat_id:)
          conv = State.get(chat_id)
          return unless conv.is_a?(Hash)

          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          game_id = conv["game_id"].to_i
          message_id = conv["message_id"]

          players = Array(conv["players"])
          ids = players.map { |h| h["id"].to_i }

          team_a_ids = Array(conv["team_a_ids"]).map(&:to_i)
          team_b_ids = Array(conv["team_b_ids"]).map(&:to_i)
          picked = Array(conv["picked_ids"]).map(&:to_i)

          text = []
          text << "*#{t.(:score_result_setup)}*"
          text << t.(:score_game_label, id: game_id)
          text << ""

          if ids.size == 2
            text << t.(:score_teams_detected_1v1)
          else
            text << t.(:score_pick_team_a) if picked.size < 2
            text << t.(:score_team_a_picked, names: Names.team_names(conv, picked)) if picked.any? && picked.size < 2
          end

          if team_a_ids.any? && team_b_ids.any?
            text << ""
            text << t.(:score_team_a, names: Names.team_names(conv, team_a_ids))
            text << t.(:score_team_b, names: Names.team_names(conv, team_b_ids))
          end

          keyboard = []

          if ids.size >= 4 && picked.size < 2
            players.each do |p|
              pid = p["id"].to_i
              next if picked.include?(pid)
              keyboard << [ { text: p["name"].to_s, callback_data: "tg_score_pick:#{game_id}:#{pid}" } ]
            end
          end

          if team_a_ids.any? && team_b_ids.any?
            keyboard << [
              { text: t.(:score_swap_btn), callback_data: "tg_score_swap:#{game_id}" },
              { text: t.(:score_enter_btn), callback_data: "tg_score_enter:#{game_id}" }
            ]
          elsif ids.size >= 4
            keyboard << [ { text: t.(:score_reset_btn), callback_data: "tg_score_reset:#{game_id}" } ]
          end

          keyboard << [ { text: t.(:back), callback_data: "tg_score_cancel:#{game_id}" } ]

          edit_or_send(chat_id:, message_id:, text: text.join("\n"), keyboard:)
        end

        def prompt_score(chat_id:, message_id:, game_id:, cb_id: nil, invalid: false)
          conv = State.get(chat_id)
          return unless conv.is_a?(Hash) && conv["game_id"].to_i == game_id

          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          team_a_ids = Array(conv["team_a_ids"]).map(&:to_i)
          team_b_ids = Array(conv["team_b_ids"]).map(&:to_i)

          if team_a_ids.empty? || team_b_ids.empty?
            render_setup(chat_id:)
            Telegram::Api.answer_callback(cb_id, t.(:score_select_teams_first), show_alert: true) rescue nil
            return
          end

          conv["flow"] = "game_stats_score_input"
          State.set(chat_id, conv.merge("message_id" => message_id))

          team_a = Names.team_names(conv, team_a_ids)
          team_b = Names.team_names(conv, team_b_ids)

          text = []
          text << "*#{t.(:score_result_title)}*"
          text << t.(:score_game_label, id: game_id)
          text << ""
          text << t.(:score_enter_instruction)
          text << "A: #{team_a}"
          text << "B: #{team_b}"
          text << ""
          text << t.(:score_example)
          text << t.(:score_send_in_chat)
          text << ""
          text << t.(:score_invalid_format) if invalid

          keyboard = [ [ { text: t.(:back), callback_data: "tg_score_cancel:#{game_id}" } ] ]

          edit_or_send(chat_id:, message_id:, text: text.join("\n"), keyboard:)
          Telegram::Api.answer_callback(cb_id) rescue nil if cb_id
        end

        def edit_or_send(chat_id:, message_id:, text:, keyboard:)
          if message_id.present?
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, keyboard) rescue nil
          else
            Telegram::Api.send_with_buttons(chat_id, text, keyboard) rescue nil
          end
        end
      end
    end
  end
end
