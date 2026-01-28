module Telegram
  module Flows
    module StatsScore
      module MessageHandler
        module_function

        def call(message)
          chat_id = message.dig("chat", "id").to_s
          text = (message["text"] || "").to_s
          return false if chat_id.blank? || text.blank?

          conv = State.get(chat_id)
          return false unless conv.is_a?(Hash)
          return false unless conv["flow"].to_s.in?(%w[game_stats_score_input game_stats_score_setup])

          game_id = conv["game_id"].to_i
          team_a_ids = Array(conv["team_a_ids"]).map(&:to_i).uniq
          team_b_ids = Array(conv["team_b_ids"]).map(&:to_i).uniq
          return false if game_id <= 0 || team_a_ids.empty? || team_b_ids.empty?

          parsed = ScoreParser.parse(text)
          unless parsed
            UI.prompt_score(chat_id:, message_id: conv["message_id"], game_id:, invalid: true)
            return true
          end

          game = Game.find_by(id: game_id)
          actor = User.find_by(telegram_chat_id: chat_id.to_s) rescue nil
          return false unless game && actor

          players = Players.for_game(game)
          return false if players.empty?

          team_a_ids &= players.map(&:id)
          team_b_ids &= players.map(&:id)
          return false if team_a_ids.empty? || team_b_ids.empty?

          mode = players.size >= 4 ? "doubles" : "singles"
          result = parsed[:result]
          played_at = game.start_at_for_ui || Time.current
          score_str = parsed[:normalized]

          MatchUpserter.call(
            game:, actor:, mode:,
            team_a_ids:, team_b_ids:,
            result:, played_at:, score: score_str
          )

          Telegram::Api.post("deleteMessage", { "chat_id" => chat_id.to_s, "message_id" => message["message_id"].to_i }) rescue nil

          State.set(chat_id, conv.slice("game_id", "page", "message_id", "fields").merge("flow" => "game_stats_menu"))
          Telegram::Flows::StatsFlow.render_menu_for(chat_id)
          true
        rescue => e
          Rails.logger.error "[Telegram::Flows::StatsScore::MessageHandler] error: #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
          false
        end
      end
    end
  end
end
