module Telegram
  module Flows
    class StatsScoreFlow
      class << self
        def handle_callback(callback_query)
          data = (callback_query["data"] || "").to_s
          cb_id = callback_query["id"]
          from = callback_query["from"] || {}
          chat_id = (callback_query.dig("message", "chat", "id") || from["id"]).to_s
          message_id = callback_query.dig("message", "message_id") || callback_query["inline_message_id"]
          return if chat_id.blank? || data.blank?

          case data
          when /\Atg_score:(\d+)\z/
            game_id = Regexp.last_match(1).to_i
            start(chat_id, message_id, cb_id, game_id)
            return

          when /\Atg_score_pick:(\d+):(\d+)\z/
            game_id = Regexp.last_match(1).to_i
            user_id = Regexp.last_match(2).to_i
            pick_player(chat_id, message_id, cb_id, game_id, user_id)
            return

          when /\Atg_score_swap:(\d+)\z/
            game_id = Regexp.last_match(1).to_i
            swap_teams(chat_id, message_id, cb_id, game_id)
            return

          when /\Atg_score_reset:(\d+)\z/
            game_id = Regexp.last_match(1).to_i
            reset(chat_id, message_id, cb_id, game_id)
            return

          when /\Atg_score_enter:(\d+)\z/
            game_id = Regexp.last_match(1).to_i
            prompt_score(chat_id, message_id, cb_id, game_id)
            return

          when /\Atg_score_cancel:(\d+)\z/
            game_id = Regexp.last_match(1).to_i
            back_to_stats_menu(chat_id, cb_id, game_id, message_id)
            return
          end

          nil
        rescue => e
          Rails.logger.error "[Telegram::Flows::StatsScoreFlow] handle_callback error: #{e.class}: #{e.message}"
          Telegram::Api.answer_callback(cb_id, "Error.", show_alert: true) rescue nil
          nil
        end

        # Returns true if message consumed
        def handle_message(message)
          chat_id = message.dig("chat", "id").to_s
          text = (message["text"] || "").to_s
          return false if chat_id.blank? || text.blank?

          conv = Telegram::Helpers::Conversation.get(chat_id) rescue {}
          return false unless conv.is_a?(Hash)
          return false unless conv["flow"] == "game_stats_score_input"

          game_id = conv["game_id"].to_i
          team_a_ids = Array(conv["team_a_ids"]).map(&:to_i).uniq
          team_b_ids = Array(conv["team_b_ids"]).map(&:to_i).uniq
          return false if game_id <= 0 || team_a_ids.empty? || team_b_ids.empty?

          parsed = parse_score(text)
          unless parsed
            prompt_score(chat_id, conv["message_id"], nil, game_id, invalid: true)
            return true
          end

          game = Game.find_by(id: game_id)
          actor = User.find_by(telegram_chat_id: chat_id.to_s) rescue nil
          return false unless game && actor

          players = players_for_game(game)
          return false if players.empty?

          # normalize: filter ids to actual players
          team_a_ids &= players.map(&:id)
          team_b_ids &= players.map(&:id)
          return false if team_a_ids.empty? || team_b_ids.empty?

          mode = players.size >= 4 ? "doubles" : "singles"
          winner = parsed[:winner] # :a or :b

          played_at = game.start_at_for_ui || Time.current
          score_str = parsed[:normalized]

          upsert_all_matches!(
            game: game,
            actor: actor,
            mode: mode,
            team_a_ids: team_a_ids,
            team_b_ids: team_b_ids,
            winner: winner,
            played_at: played_at,
            score: score_str
          )

          Telegram::Api.post(
            "deleteMessage",
            { "chat_id" => chat_id.to_s, "message_id" => message["message_id"].to_i }
          ) rescue nil

          Telegram::Api.answer_callback(nil) rescue nil

          # go back to stats menu, preserving fields
          Telegram::Helpers::Conversation.set(
            chat_id,
            conv.slice("game_id", "page", "message_id", "fields").merge("flow" => "game_stats_menu")
          ) rescue nil

          Telegram::Flows::StatsFlow.render_menu_for(chat_id)
          true
        rescue => e
          Rails.logger.error "[Telegram::Flows::StatsScoreFlow] handle_message error: #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n") }"
          false
        end

        private

        def start(chat_id, message_id, cb_id, game_id)
          game = Game.find_by(id: game_id)
          unless game
            Telegram::Api.answer_callback(cb_id, "Game not found.", show_alert: true) rescue nil
            return
          end

          actor = User.find_by(telegram_chat_id: chat_id.to_s) rescue nil
          unless actor && (actor.admin? || actor.id == game.user_id)
            Telegram::Api.answer_callback(cb_id, "Only the game creator or an admin can fill statistics.", show_alert: true) rescue nil
            return
          end

          players = players_for_game(game)
          if players.size < 2
            Telegram::Api.answer_callback(cb_id, "Not enough players to record a result.", show_alert: true) rescue nil
            return
          end

          conv = Telegram::Helpers::Conversation.get(chat_id) rescue {}
          fields = (conv.is_a?(Hash) && conv["fields"].is_a?(Hash)) ? conv["fields"] : {}
          page = (conv.is_a?(Hash) && conv["page"].to_i > 0) ? conv["page"].to_i : 1

          state = {
            "flow" => "game_stats_score_setup",
            "game_id" => game_id,
            "page" => page,
            "message_id" => message_id,
            "fields" => fields,
            "players" => players.map { |u| { "id" => u.id, "name" => display_name(u) } }
          }

          if players.size == 2
            a = players[0]
            b = players[1]
            state["team_a_ids"] = [ a.id ]
            state["team_b_ids"] = [ b.id ]
          else
            state["team_a_ids"] = []
            state["team_b_ids"] = []
            state["picked_ids"] = []
          end

          Telegram::Helpers::Conversation.set(chat_id, state) rescue nil

          render_setup(chat_id)
          Telegram::Api.answer_callback(cb_id) rescue nil
        end

        def reset(chat_id, message_id, cb_id, game_id)
          conv = Telegram::Helpers::Conversation.get(chat_id) rescue {}
          return unless conv.is_a?(Hash) && conv["game_id"].to_i == game_id

          conv["flow"] = "game_stats_score_setup"
          conv["message_id"] = message_id if message_id.present?
          conv["picked_ids"] = []
          conv["team_a_ids"] = []
          conv["team_b_ids"] = []

          Telegram::Helpers::Conversation.set(chat_id, conv) rescue nil
          render_setup(chat_id)
          Telegram::Api.answer_callback(cb_id) rescue nil
        end

        def pick_player(chat_id, message_id, cb_id, game_id, user_id)
          conv = Telegram::Helpers::Conversation.get(chat_id) rescue {}
          return unless conv.is_a?(Hash) && conv["flow"] == "game_stats_score_setup" && conv["game_id"].to_i == game_id

          players = Array(conv["players"]).map { |h| h["id"].to_i }
          return unless players.include?(user_id)

          picked = Array(conv["picked_ids"]).map(&:to_i)
          return if picked.include?(user_id)

          picked << user_id
          conv["picked_ids"] = picked

          if picked.size == 2
            team_a_ids = picked
            team_b_ids = players - picked
            conv["team_a_ids"] = team_a_ids
            conv["team_b_ids"] = team_b_ids
          end

          Telegram::Helpers::Conversation.set(chat_id, conv.merge("message_id" => message_id)) rescue nil
          render_setup(chat_id)
          Telegram::Api.answer_callback(cb_id) rescue nil
        end

        def swap_teams(chat_id, message_id, cb_id, game_id)
          conv = Telegram::Helpers::Conversation.get(chat_id) rescue {}
          return unless conv.is_a?(Hash) && conv["game_id"].to_i == game_id

          a = Array(conv["team_a_ids"]).map(&:to_i)
          b = Array(conv["team_b_ids"]).map(&:to_i)
          conv["team_a_ids"] = b
          conv["team_b_ids"] = a

          Telegram::Helpers::Conversation.set(chat_id, conv.merge("message_id" => message_id)) rescue nil
          render_setup(chat_id)
          Telegram::Api.answer_callback(cb_id) rescue nil
        end

        def prompt_score(chat_id, message_id, cb_id, game_id, invalid: false)
          conv = Telegram::Helpers::Conversation.get(chat_id) rescue {}
          return unless conv.is_a?(Hash) && conv["game_id"].to_i == game_id

          team_a_ids = Array(conv["team_a_ids"]).map(&:to_i)
          team_b_ids = Array(conv["team_b_ids"]).map(&:to_i)

          if team_a_ids.empty? || team_b_ids.empty?
            render_setup(chat_id)
            Telegram::Api.answer_callback(cb_id, "Select teams first.", show_alert: true) rescue nil
            return
          end

          conv["flow"] = "game_stats_score_input"
          Telegram::Helpers::Conversation.set(chat_id, conv.merge("message_id" => message_id)) rescue nil

          team_a = team_names(conv, team_a_ids)
          team_b = team_names(conv, team_b_ids)

          text = []
          text << "*Result*"
          text << "Game ##{game_id}"
          text << ""
          text << "Enter set score as Team A vs Team B:"
          text << "A: #{team_a}"
          text << "B: #{team_b}"
          text << ""
          text << "Example: `6-4 6-3` or `6:4 3:6 10:8`"
          text << "Please send score in chat."
          text << ""
          text << "Invalid score format, try again." if invalid

          keyboard = [
            [ { text: "Back", callback_data: "tg_score_cancel:#{game_id}" } ]
          ]

          if message_id.present?
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, text.join("\n"), keyboard) rescue nil
          else
            Telegram::Api.send_with_buttons(chat_id, text.join("\n"), keyboard) rescue nil
          end

          Telegram::Api.answer_callback(cb_id) rescue nil if cb_id
        end

        def render_setup(chat_id)
          conv = Telegram::Helpers::Conversation.get(chat_id) rescue {}
          return unless conv.is_a?(Hash)

          game_id = conv["game_id"].to_i
          message_id = conv["message_id"]

          players = Array(conv["players"]) # [{id,name}]
          ids = players.map { |h| h["id"].to_i }

          team_a_ids = Array(conv["team_a_ids"]).map(&:to_i)
          team_b_ids = Array(conv["team_b_ids"]).map(&:to_i)
          picked = Array(conv["picked_ids"]).map(&:to_i)

          text = []
          text << "*Result setup*"
          text << "Game ##{game_id}"
          text << ""

          if ids.size == 2
            text << "Teams detected (1v1)."
          else
            text << "Pick 2 players for Team A:" if picked.size < 2
            text << "Team A picked: #{team_names(conv, picked)}" if picked.any? && picked.size < 2
          end

          if team_a_ids.any? && team_b_ids.any?
            text << ""
            text << "Team A: #{team_names(conv, team_a_ids)}"
            text << "Team B: #{team_names(conv, team_b_ids)}"
          end

          keyboard = []

          if ids.size >= 4 && (picked.size < 2)
            players.each do |p|
              pid = p["id"].to_i
              next if picked.include?(pid)
              keyboard << [ { text: p["name"].to_s, callback_data: "tg_score_pick:#{game_id}:#{pid}" } ]
            end
          end

          if team_a_ids.any? && team_b_ids.any?
            keyboard << [
              { text: "Swap A/B", callback_data: "tg_score_swap:#{game_id}" },
              { text: "Enter score", callback_data: "tg_score_enter:#{game_id}" }
            ]
          else
            keyboard << [ { text: "Reset", callback_data: "tg_score_reset:#{game_id}" } ] if ids.size >= 4
          end

          keyboard << [ { text: "Back", callback_data: "tg_score_cancel:#{game_id}" } ]

          if message_id.present?
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, text.join("\n"), keyboard) rescue nil
          else
            Telegram::Api.send_with_buttons(chat_id, text.join("\n"), keyboard) rescue nil
          end
        end

        def back_to_stats_menu(chat_id, cb_id, game_id, message_id)
          conv = Telegram::Helpers::Conversation.get(chat_id) rescue {}
          fields = (conv.is_a?(Hash) && conv["fields"].is_a?(Hash)) ? conv["fields"] : {}
          page = (conv.is_a?(Hash) && conv["page"].to_i > 0) ? conv["page"].to_i : 1

          Telegram::Helpers::Conversation.set(
            chat_id,
            {
              "flow" => "game_stats_menu",
              "game_id" => game_id,
              "page" => page,
              "message_id" => message_id || (conv.is_a?(Hash) ? conv["message_id"] : nil),
              "fields" => fields
            }
          ) rescue nil

          Telegram::Flows::StatsFlow.render_menu_for(chat_id)
          Telegram::Api.answer_callback(cb_id) rescue nil if cb_id
        end

        def players_for_game(game)
          users = []
          users << game.user
          users.concat(game.participations.includes(:user).map(&:user))
          users.compact.uniq { |u| u.id }
        rescue
          []
        end

        def display_name(user)
          user.name.to_s.strip.presence || user.telegram_username.to_s.strip.presence || user.email.to_s
        end

        def team_names(conv, ids)
          players = Array(conv["players"]).map { |h| [ h["id"].to_i, h["name"].to_s ] }.to_h
          Array(ids).map { |id| players[id.to_i] || "##{id}" }.join(" + ")
        end

        def parse_score(text)
          raw = text.to_s.strip
          return nil if raw.empty?

          # accept: "6-4 6-3" or "6:4, 3:6, 10:8"
          tokens = raw.split(/[\s,]+/).map(&:strip).reject(&:empty?)
          sets = []

          tokens.each do |tok|
            m = tok.match(/\A(\d{1,2})\s*[-:]\s*(\d{1,2})\z/)
            return nil unless m
            a = m[1].to_i
            b = m[2].to_i
            sets << [ a, b ]
          end

          return nil if sets.empty?

          a_sets = sets.count { |a, b| a > b }
          b_sets = sets.count { |a, b| b > a }
          return nil if a_sets == b_sets

          normalized = sets.map { |a, b| "#{a}-#{b}" }.join(" ")

          { normalized: normalized, winner: (a_sets > b_sets ? :a : :b) }
        end

        def upsert_all_matches!(game:, actor:, mode:, team_a_ids:, team_b_ids:, winner:, played_at:, score:)
          team_a_ids = team_a_ids.map(&:to_i)
          team_b_ids = team_b_ids.map(&:to_i)

          all_ids = (team_a_ids + team_b_ids).uniq
          users = User.where(id: all_ids).to_a
          by_id = users.index_by(&:id)

          team_a_ids.each do |uid|
            user = by_id[uid]
            next unless user

            opponent = (mode == "singles") ? by_id[team_b_ids.first] : nil
            stats = {
              "entered_by" => actor.id,
              "team_a_ids" => team_a_ids,
              "team_b_ids" => team_b_ids,
              "partner_id" => (mode == "doubles" ? (team_a_ids - [ uid ]).first : nil),
              "opponent_ids" => (mode == "doubles" ? team_b_ids : [ team_b_ids.first ].compact)
            }.compact

            PlayerStatistics::UpsertMatchForGameService.new(
              user: user,
              game: game,
              actor: actor,
              mode: mode,
              won: (winner == :a),
              played_at: played_at,
              opponent: opponent,
              score: score,
              stats: stats
            ).call
          end

          team_b_ids.each do |uid|
            user = by_id[uid]
            next unless user

            opponent = (mode == "singles") ? by_id[team_a_ids.first] : nil
            stats = {
              "entered_by" => actor.id,
              "team_a_ids" => team_a_ids,
              "team_b_ids" => team_b_ids,
              "partner_id" => (mode == "doubles" ? (team_b_ids - [ uid ]).first : nil),
              "opponent_ids" => (mode == "doubles" ? team_a_ids : [ team_a_ids.first ].compact)
            }.compact

            PlayerStatistics::UpsertMatchForGameService.new(
              user: user,
              game: game,
              actor: actor,
              mode: mode,
              won: (winner == :b),
              played_at: played_at,
              opponent: opponent,
              score: score,
              stats: stats
            ).call
          end
        end
      end
    end
  end
end
