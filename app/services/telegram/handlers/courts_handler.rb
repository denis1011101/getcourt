module Telegram
  module Handlers
    class CourtsHandler
      PER_PAGE = 5

      class << self
        include Telegram::Handlers::ReplyHelpers

        def menu(chat_id, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          buttons = [
            [{ text: t.(:all_courts),    callback_data: "menu:courts:page:1" }],
            [{ text: t.(:main_menu_btn), callback_data: "menu:main" }]
          ]

          send_or_edit_with_buttons(chat_id, t.(:courts_menu), buttons, message_id: message_id)
        end

        def game_label(g, locale: Telegram::I18n::DEFAULT_LOCALE)
          Telegram::Handlers::GamesHandler.game_label(g, locale: locale)
        end

        def list_page(chat_id, page = 1, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          page = page.to_i < 1 ? 1 : page.to_i
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          scope = Court.visible_to(user)
          total = scope.count
          pages = [(total.to_f / PER_PAGE).ceil, 1].max
          offset = (page - 1) * PER_PAGE
          courts = scope.order("id ASC").offset(offset).limit(PER_PAGE)
          header = t.(:courts_page, page: page, pages: pages)

          if courts.empty?
            send_or_edit_text(chat_id, "#{header}\n\n#{t.(:no_courts_on_page)}", message_id: message_id)
            return
          end

          buttons = courts.map do |c|
            label = (c.respond_to?(:name) && c.name.present?) ? c.name : "Court ##{c.id}"
            [{ text: label, callback_data: "court:show:#{c.id}:#{page}" }]
          end

          nav = []
          nav << [{ text: t.(:prev_page), callback_data: "menu:courts:page:#{page - 1}" }] if page > 1
          nav << [{ text: t.(:next_page), callback_data: "menu:courts:page:#{page + 1}" }] if page < pages
          buttons.concat(nav) unless nav.empty?

          buttons << [{ text: t.(:main_menu_btn), callback_data: "menu:main" }]

          send_or_edit_with_buttons(chat_id, header, buttons, message_id: message_id)
        end

        def list_games(chat_id, court_id, page = 1, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          page = page.to_i < 1 ? 1 : page.to_i
          total = Game.where(court_id: court_id).count
          pages = [(total.to_f / PER_PAGE).ceil, 1].max
          offset = (page - 1) * PER_PAGE
          games = Game.where(court_id: court_id).order(date: :desc).offset(offset).limit(PER_PAGE)
          header = t.(:games_on_court_page, court_id: court_id, page: page, pages: pages)

          if games.empty?
            buttons = [
              [{ text: t.(:back_to_court), callback_data: "court:show:#{court_id}:#{page}" }],
              [{ text: t.(:main_menu_btn), callback_data: "menu:main" }]
            ]

            send_or_edit_with_buttons(
              chat_id,
              "#{header}\n\n#{t.(:no_games_on_court_page)}",
              buttons,
              message_id: message_id
            )
            return
          end

          buttons = games.map do |g|
            label = Telegram::Handlers::GamesHandler.game_label(g, locale: locale)
            [{ text: label, callback_data: "game:show:#{g.id}:1" }]
          end

          nav = []
          nav << [{ text: t.(:prev_page), callback_data: "court:games:#{court_id}:#{page - 1}" }] if page > 1
          nav << [{ text: t.(:next_page), callback_data: "court:games:#{court_id}:#{page + 1}" }] if page < pages
          buttons.concat(nav) unless nav.empty?

          buttons << [{ text: t.(:back_to_court), callback_data: "court:show:#{court_id}:#{page}" }]

          send_or_edit_with_buttons(chat_id, header, buttons, message_id: message_id)
        end

        def show_court(chat_id, court_id, page = 1, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          court = Court.visible_to(user).find_by(id: court_id)
          return Telegram::Api.send_simple(chat_id, t.(:court_not_found)) unless court

          header = "Court ##{court.id}"
          text = "#{header}\n\n#{court.name.to_s}"

          buttons = []
          buttons << [{ text: t.(:create_game), callback_data: "create_game_from_court:#{court.id}" }]
          buttons << [{ text: t.(:list_of_games), callback_data: "court:games:#{court.id}:1" }]
          buttons << [{ text: t.(:back_to_courts), callback_data: "menu:courts:page:#{page}" }]

          send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
        end
      end
    end
  end
end
