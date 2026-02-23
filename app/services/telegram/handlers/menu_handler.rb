module Telegram
  module Handlers
    class MenuHandler
      class << self
        include Telegram::Handlers::ReplyHelpers

        def menu(chat_id, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          text = t.(:main_menu)
          buttons = [
            [ { text: t.(:create_game),              callback_data: "game:create" } ],
            [ { text: t.(:find_game),                 callback_data: "menu:games:page:1" } ],
            [ { text: t.(:create_tournament),         callback_data: "tournament:create" } ],
            [ { text: t.(:find_tournament),            callback_data: "menu:tournaments:page:1" } ],
            [ { text: t.(:my_games),                   callback_data: "menu:my_games:page:1" },
              { text: t.(:my_tournaments),             callback_data: "menu:my_tournaments:page:1" } ],
            [ { text: t.(:find_coach),                callback_data: "menu:find_coach:page:1" } ],
            [ { text: t.(:games_looking_for_player),  callback_data: "menu:games_need_players:page:1" } ],
            [ { text: t.(:tennis_life),               callback_data: "menu:tennis_life" } ],
            [ { text: t.(:profile),                   callback_data: "profile:show" } ]
          ]

          send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
        end
      end
    end
  end
end
