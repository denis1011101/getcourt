module Telegram
  module Handlers
    class TournamentsHandler
      PER_PAGE = 5

      class << self
        include Telegram::Handlers::ReplyHelpers

        # Formatted label for tournament list items
        def tournament_label(t, locale: Telegram::I18n::DEFAULT_LOCALE)
          name = t.name.presence || "Tournament ##{t.id}"
          joined = approved_participants_count(t.tournament_participants)
          total = t.players_count.to_i
          players_text = total > 0 ? "#{joined}/#{total}" : "#{joined}"
          date_str = t.start_date.present? ? t.start_date.strftime("%d.%m") : nil

          parts = [ name ]
          parts << date_str if date_str
          parts << players_text
          parts.join(" — ")
        end

        # Paginated tournament list
        def list_page(chat_id, page = 1, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          page = [ page.to_i, 1 ].max

          tournaments = Tournament.includes(:tournament_participants).order(created_at: :desc).to_a

          total = tournaments.size
          pages = [ (total.to_f / PER_PAGE).ceil, 1 ].max
          offset = (page - 1) * PER_PAGE
          slice = tournaments.slice(offset, PER_PAGE) || []

          header = t.(:tournaments_page, page: page, pages: pages)

          if slice.empty?
            send_or_edit_text(chat_id, "#{header}\n\n#{t.(:no_tournaments_on_page)}", message_id: message_id)
            return
          end

          buttons = slice.map do |tour|
            [ { text: tournament_label(tour, locale: locale), callback_data: "tournament:show:#{tour.id}:#{page}" } ]
          end

          nav = []
          nav << [ { text: t.(:prev_page), callback_data: "menu:tournaments:page:#{page - 1}" } ] if page > 1
          nav << [ { text: t.(:next_page), callback_data: "menu:tournaments:page:#{page + 1}" } ] if page < pages
          buttons.concat(nav) unless nav.empty?

          buttons << [ { text: t.(:main_menu_btn), callback_data: "menu:main" } ]

          send_or_edit_with_buttons(chat_id, header, buttons, message_id: message_id)
        end

        # My tournaments (filtered by user)
        def my_tournaments_page(chat_id, page = 1, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t_fn = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          unless user
            send_or_edit_text(chat_id, t_fn.(:no_linked_account), message_id: message_id)
            return
          end

          page = [ page.to_i, 1 ].max

          tournaments = Tournament.includes(:tournament_participants)
                                  .where("tournaments.user_id = :uid OR tournaments.id IN (SELECT tournament_id FROM tournament_participants WHERE user_id = :uid)", uid: user.id)
                                  .order(created_at: :desc).to_a

          total = tournaments.size
          pages = [ (total.to_f / PER_PAGE).ceil, 1 ].max
          offset = (page - 1) * PER_PAGE
          slice = tournaments.slice(offset, PER_PAGE) || []

          header = t_fn.(:my_tournaments_page, page: page, pages: pages)

          if slice.empty?
            buttons = [ [ { text: t_fn.(:main_menu_btn), callback_data: "menu:main" } ] ]
            send_or_edit_with_buttons(chat_id, "#{header}\n\n#{t_fn.(:no_my_tournaments)}", buttons, message_id: message_id)
            return
          end

          buttons = slice.map do |tour|
            [ { text: tournament_label(tour, locale: locale), callback_data: "tournament:show:#{tour.id}:#{page}" } ]
          end

          nav = []
          nav << [ { text: t_fn.(:prev_page), callback_data: "menu:my_tournaments:page:#{page - 1}" } ] if page > 1
          nav << [ { text: t_fn.(:next_page), callback_data: "menu:my_tournaments:page:#{page + 1}" } ] if page < pages
          buttons.concat(nav) unless nav.empty?

          buttons << [ { text: t_fn.(:main_menu_btn), callback_data: "menu:main" } ]

          send_or_edit_with_buttons(chat_id, header, buttons, message_id: message_id)
        end

        # Show tournament card with action buttons
        def show_tournament(chat_id, tournament_id, page = 1, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          tournament = Tournament.find_by(id: tournament_id)
          return Telegram::Api.send_simple(chat_id, t.(:tournament_not_found)) unless tournament

          joined = approved_participants_count(tournament.tournament_participants)
          capacity = tournament.players_count.to_i > 0 ? tournament.players_count.to_i : "?"
          owner = User.find_by(id: tournament.user_id)
          owner_name = Telegram::Helpers::UserLookup.display_name(owner, fallback: "—")

          host = ENV.fetch("APP_HOST", "https://getcourt.co")
          tournament_url = "#{host}/tournaments/#{tournament.id}"

          lines = []
          name = tournament.name.presence || "Tournament"
          lines << "*#{name} \\##{tournament.id}*"
          lines << t.(:tournament_format_label, format: tournament.format&.humanize || "—") if tournament.format.present?

          if tournament.start_date.present?
            dates = tournament.start_date.strftime("%d.%m.%Y")
            dates += " — #{tournament.end_date.strftime("%d.%m.%Y")}" if tournament.end_date.present?
            dates += " #{tournament.time.strftime("%H:%M")}" if tournament.time.present?
            lines << t.(:tournament_dates_label, dates: dates)
          end

          lines << t.(:tournament_players, count: joined, capacity: capacity)

          if tournament.games.count > 0
            lines << t.(:tournament_games_label, count: tournament.games.count)
          end

          lines << t.(:tournament_owner, name: owner_name)

          text = lines.compact.join("\n")

          buttons = []

          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          if user
            participant = tournament.tournament_participants.find_by(user_id: user.id)
            if participant&.pending?
              request_text = locale.to_s == "ru" ? "Запрос отправлен" : "Request sent"
              buttons << [ { text: request_text, callback_data: "tournament:join_pending:#{tournament.id}:#{page}" } ]
            elsif participant
              buttons << [ { text: t.(:leave_tournament), callback_data: "tournament:leave:#{tournament.id}:#{page}" } ]
            else
              buttons << [ { text: t.(:join_tournament), callback_data: "tournament:join:#{tournament.id}:#{page}" } ]
            end

            if tournament.user_id == user.id
              buttons << [ { text: t.(:invite_players), callback_data: "tournament:invite:#{tournament.id}:#{page}" } ]
              buttons << [ { text: t.(:manage_players), callback_data: "tournament:manage:#{tournament.id}:#{page}" } ]
              buttons << [ { text: t.(:edit_tournament), callback_data: "tournament:edit:#{tournament.id}:#{page}" } ]
              buttons << [ { text: t.(:delete_tournament), callback_data: "tournament:delete:#{tournament.id}:#{page}" } ]
            end

            if tournament.round_robin?
              buttons << [ { text: t.(:tournament_rr_standings), callback_data: "tournament:rr_standings:#{tournament.id}:#{page}" } ]
            end

            if tournament.user_id == user.id && tournament.started? && tournament.round_robin?
              buttons << [ { text: t.(:tournament_rr_add_match), callback_data: "tournament:rr_add_match:#{tournament.id}:#{page}" } ]
            elsif tournament.user_id == user.id && tournament.started?
              buttons << [ { text: t.(:add_tournament_result), callback_data: "tournament:add_result:#{tournament.id}:#{page}" } ]
            end
          end

          buttons << [ { text: t.(:open_in_browser), url: tournament_url } ] unless host.to_s.include?("localhost")
          buttons << [ { text: t.(:back_to_tournaments), callback_data: "menu:tournaments:page:#{page}" } ]

          send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
        end

        def approved_participants_count(scope)
          return scope.approved.count unless scope.loaded?
          scope.count(&:approved?)
        end
      end
    end
  end
end
