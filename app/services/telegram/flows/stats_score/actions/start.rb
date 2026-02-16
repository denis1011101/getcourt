module Telegram
  module Flows
    module StatsScore
      module Actions
        module Start
          module_function

          def call(chat_id:, message_id:, cb_id:, game_id:)
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

            players = StatsScore::Players.for_game(game)
            if players.size < 2
              Telegram::Api.answer_callback(cb_id, "Not enough players to record a result.", show_alert: true) rescue nil
              return
            end

            conv = StatsScore::State.get(chat_id)
            fields, page = StatsScore::State.fields_and_page_from(conv)

            state = {
              "flow" => "game_stats_score_setup",
              "game_id" => game_id,
              "page" => page,
              "message_id" => message_id,
              "fields" => fields,
              "players" => players.map { |u| { "id" => u.id, "name" => StatsScore::Names.display_name(u) } }
            }

            if players.size == 2
              state["team_a_ids"] = [ players[0].id ]
              state["team_b_ids"] = [ players[1].id ]
            else
              state["team_a_ids"] = []
              state["team_b_ids"] = []
              state["picked_ids"] = []
            end

            StatsScore::State.set(chat_id, state)
            StatsScore::Ui.render_setup(chat_id:)
            Telegram::Api.answer_callback(cb_id) rescue nil
          end
        end
      end
    end
  end
end
