module Telegram
  module Handlers
    class GamesHandler
      class << self
        include Telegram::Handlers::ReplyHelpers

        def menu(chat_id, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          buttons = [
            [ { text: t.(:all_games), callback_data: "menu:games:page:1" } ],
            [ { text: t.(:create_game), callback_data: "game:create" } ],
            [ { text: t.(:main_menu_btn), callback_data: "menu:main" } ]
          ]
          send_or_edit_with_buttons(chat_id, t.(:games_menu), buttons, message_id: message_id)
        end

        def owner_display(user)
          Telegram::Helpers::UserLookup.display_name(user)
        end

        # Return label used in games lists (shared formatter used everywhere)
        # locale: pass the active locale so spots-left text is correctly localised
        def game_label(g, owner: nil, locale: Telegram::I18n::DEFAULT_LOCALE)
          date = Telegram::Helpers::GameFormatting.game_datetime(g)
          title = Telegram::Helpers::GameFormatting.game_title(g)

          required = (g.respond_to?(:players_count) && g.players_count.to_i > 0) ? g.players_count.to_i : 4
          approved_count =
            if g.participations.loaded?
              g.participations.select { |p| p.respond_to?(:approved?) ? p.approved? : (p.status == "approved") }.size
            else
              g.participations.respond_to?(:approved) ? g.participations.approved.count : g.participations.count
            end
          taken = approved_count
          spots_left = required - taken
          spots_left = 0 if spots_left.negative?
          spots_text = Telegram::I18n.spots_left_text(spots_left, locale: locale)

          title_with_id = "#{title || (g.respond_to?(:title) && g.title.to_s.presence) || 'Game'} ##{g.id}"
          [ title_with_id, date, spots_text ].compact.join(" — ")
        end

        def list_page(chat_id, page = 1, message_id: nil)
          Telegram::Handlers::GamesListHandler.list_page(chat_id, page, message_id: message_id)
        end

        def my_games_page(chat_id, page = 1, message_id: nil)
          Telegram::Handlers::GamesListHandler.my_games_page(chat_id, page, message_id: message_id)
        end

        def show_game(chat_id, game_id, page = 1, message_id: nil)
          Telegram::Handlers::GameDetailHandler.show_game(chat_id, game_id, page, message_id: message_id)
        end

        def show_players(chat_id, game_id, page = 1, message_id: nil)
          Telegram::Handlers::GameDetailHandler.show_players(chat_id, game_id, page, message_id: message_id)
        end
      end
    end
  end
end
