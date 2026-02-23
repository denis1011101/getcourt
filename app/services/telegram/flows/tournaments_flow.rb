module Telegram
  module Flows
    class TournamentsFlow
      # Step-by-step tournament creation + join/leave/show callbacks
      #
      # Steps: name, players_count, games_count, format, court, start_date, start_time
      # Conversation state stored via Telegram::Helpers::Conversation with flow: "create_tournament"

      STEPS = %w[name players_count games_count format court start_date start_time].freeze
      TOTAL_STEPS = STEPS.size

      class << self
        def handle_callback(callback)
          cb = Telegram::Helpers::CallbackData.parse(callback)
          locale = Telegram::Helpers::UserLookup.locale_for(cb.chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          case cb.data
          # --- Create flow ---
          when /\Atournament:create\z/
            start_create(cb.chat_id, cb_id: cb.cb_id, message_id: cb.message_id)

          when /\Atournament:create:bot\z/
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            conv = Telegram::Helpers::Conversation.get(cb.chat_id)
            return unless conv["flow"] == "create_tournament"
            conv["step"] = "name"
            message_id = conv["message_id"] || cb.message_id
            conv["message_id"] = message_id if message_id
            Telegram::Helpers::Conversation.set(cb.chat_id, conv)
            send_step_prompt(cb.chat_id, "name", message_id: message_id)

          when /\Atournament:create:cancel\z/
            Telegram::Api.answer_callback(cb.cb_id, t.(:create_tournament_cancelled)) rescue nil
            Telegram::Helpers::Conversation.finish(cb.chat_id)
            Telegram::Handlers::MenuHandler.menu(cb.chat_id, message_id: cb.message_id)

          when /\Atournament:create:skip\z/
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            conv = Telegram::Helpers::Conversation.get(cb.chat_id)
            handle_skip(cb.chat_id, conv["message_id"] || cb.message_id)

          when /\Atournament:create:players:(\d+)\z/
            count = $1.to_i
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            conv = Telegram::Helpers::Conversation.get(cb.chat_id)
            conv["fields"] ||= {}
            conv["fields"]["players_count"] = count
            save_and_advance(cb.chat_id, conv, "players_count", message_id: conv["message_id"] || cb.message_id)

          when /\Atournament:create:players:other\z/
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            conv = Telegram::Helpers::Conversation.get(cb.chat_id)
            return unless conv["flow"] == "create_tournament"
            conv["step"] = "players_count"
            message_id = conv["message_id"] || cb.message_id
            conv["message_id"] = message_id if message_id
            Telegram::Helpers::Conversation.set(cb.chat_id, conv)
            send_players_count_input_prompt(cb.chat_id, message_id: message_id)

          when /\Atournament:create:games_count:(\d+)\z/
            count = $1.to_i
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            conv = Telegram::Helpers::Conversation.get(cb.chat_id)
            conv["fields"] ||= {}
            conv["fields"]["games_count"] = count
            save_and_advance(cb.chat_id, conv, "games_count", message_id: conv["message_id"] || cb.message_id)

          when /\Atournament:create:format:(singles|doubles)\z/
            fmt = $1
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            conv = Telegram::Helpers::Conversation.get(cb.chat_id)
            conv["fields"] ||= {}
            conv["fields"]["format"] = fmt
            save_and_advance(cb.chat_id, conv, "format", message_id: conv["message_id"] || cb.message_id)

          when /\Atournament:create:court:(\d+)\z/
            court_id = $1.to_i
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            conv = Telegram::Helpers::Conversation.get(cb.chat_id)
            conv["fields"] ||= {}
            conv["fields"]["court_id"] = court_id
            save_and_advance(cb.chat_id, conv, "court", message_id: conv["message_id"] || cb.message_id)

          when /\Atournament:create:court_page:(\d+)\z/
            page = $1.to_i
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            conv = Telegram::Helpers::Conversation.get(cb.chat_id)
            send_court_selection(cb.chat_id, page, message_id: conv["message_id"] || cb.message_id)

          when /\Atournament:create:court_new\z/
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            conv = Telegram::Helpers::Conversation.get(cb.chat_id)
            tournament_fields = conv["fields"] || {}
            Rails.cache.write("tg:tournament_create_fields:#{cb.chat_id}", tournament_fields, expires_in: 2.hours)
            Telegram::Flows::CourtCreateFlow.start(cb.chat_id, return_to: "tournament_create", message_id: conv["message_id"] || cb.message_id)

          # --- Add result flow ---
          when /\Atournament:add_result:(\d+)(?::(\d+))?\z/
            tid = $1.to_i
            page = ($2 || 1).to_i
            start_add_result(cb.chat_id, tid, page, cb_id: cb.cb_id, message_id: cb.message_id)

          when /\Atournament:add_result:user:(\d+)\z/
            user_id = $1.to_i
            conv = Telegram::Helpers::Conversation.get(cb.chat_id)
            handle_add_result_user(cb.chat_id, conv, user_id, cb_id: cb.cb_id, message_id: cb.message_id)

          when /\Atournament:add_result:skip_hours\z/
            conv = Telegram::Helpers::Conversation.get(cb.chat_id)
            handle_add_result_skip_hours(cb.chat_id, conv, cb_id: cb.cb_id, message_id: cb.message_id)

          when /\Atournament:add_result:cancel\z/
            conv = Telegram::Helpers::Conversation.get(cb.chat_id)
            cancel_add_result(cb.chat_id, conv, cb_id: cb.cb_id, message_id: cb.message_id)

          # --- Invite flow ---
          when /\Atournament:invite:(\d+)(?::(\d+))?\z/
            tid = $1.to_i
            page = ($2 || 1).to_i
            start_invite(cb.chat_id, tid, page, cb_id: cb.cb_id, message_id: cb.message_id)

          when /\Atournament:invite_cancel:(\d+)(?::(\d+))?\z/
            tid = $1.to_i
            page = ($2 || 1).to_i
            cancel_invite(cb.chat_id, tid, page, cb_id: cb.cb_id, message_id: cb.message_id)

          when /\Atournament:invite_decline:(\d+)\z/
            tid = $1.to_i
            handle_invite_decline(cb.chat_id, tid, cb_id: cb.cb_id, message_id: cb.message_id)

          # --- Show/Join/Leave ---
          when /\Atournament:show:(\d+)(?::(\d+))?\z/
            tid = $1.to_i
            page = ($2 || 1).to_i
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            Telegram::Handlers::TournamentsHandler.show_tournament(cb.chat_id, tid, page, message_id: cb.message_id)

          when /\Atournament:join:(\d+)(?::(\d+))?\z/
            tid = $1.to_i
            page = ($2 || 1).to_i
            handle_join(cb.chat_id, tid, page, cb_id: cb.cb_id, message_id: cb.message_id)

          when /\Atournament:leave:(\d+)(?::(\d+))?\z/
            tid = $1.to_i
            page = ($2 || 1).to_i
            handle_leave(cb.chat_id, tid, page, cb_id: cb.cb_id, message_id: cb.message_id)

          else
            Telegram::Api.answer_callback(cb.cb_id, t.(:unknown_action), show_alert: false) rescue nil
          end
        rescue => e
          Rails.logger.error "[Telegram::Flows::TournamentsFlow] callback error: #{e.class} #{e.message}"
        end

        # Called by ReplyProcessor when flow == "create_tournament"
        def process_text(message)
          chat_id = (message.dig("chat", "id") || message.dig("from", "id")).to_s
          text = message["text"].to_s.strip
          conv = Telegram::Helpers::Conversation.get(chat_id)
          flow = conv["flow"]
          return false unless %w[create_tournament tournament_add_result tournament_invite].include?(flow)

          delete_input_message(message)

          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          step = conv["step"]

          if flow == "tournament_add_result"
            process_add_result_text(chat_id, conv, step, text, t)
            return true
          end

          if flow == "tournament_invite"
            process_invite_text(chat_id, conv, text, t)
            return true
          end

          case step
          when "name"
            if text.blank?
              Telegram::Api.send_simple(chat_id, t.(:create_tournament_name_invalid))
              return true
            end
            conv["fields"] ||= {}
            conv["fields"]["name"] = text
            save_and_advance(chat_id, conv, "name", message_id: conv["message_id"])

          when "players_count"
            count = text.to_i
            if count < 2
              Telegram::Api.send_simple(chat_id, t.(:create_tournament_players_invalid))
              return true
            end
            conv["fields"] ||= {}
            conv["fields"]["players_count"] = count
            save_and_advance(chat_id, conv, "players_count", message_id: conv["message_id"])

          when "games_count"
            count = text.to_i
            if count < 1
              Telegram::Api.send_simple(chat_id, t.(:create_tournament_players_invalid))
              return true
            end
            conv["fields"] ||= {}
            conv["fields"]["games_count"] = count
            save_and_advance(chat_id, conv, "games_count", message_id: conv["message_id"])

          when "start_date"
            date = begin; Date.parse(text); rescue; nil; end
            unless date
              Telegram::Api.send_simple(chat_id, t.(:create_tournament_date_invalid))
              return true
            end
            conv["fields"] ||= {}
            conv["fields"]["start_date"] = date.to_s
            save_and_advance(chat_id, conv, "start_date", message_id: conv["message_id"])

          when "start_time"
            parsed_time = parse_time_input(text)
            unless parsed_time
              Telegram::Api.send_simple(chat_id, t.(:create_tournament_time_invalid))
              return true
            end
            conv["fields"] ||= {}
            conv["fields"]["start_time"] = parsed_time.strftime("%H:%M")
            save_and_advance(chat_id, conv, "start_time", message_id: conv["message_id"])

          else
            Telegram::Api.send_simple(chat_id, t.(:please_use_buttons))
          end

          true
        rescue => e
          Rails.logger.error "[TournamentsFlow] process_text error: #{e.class} #{e.message}"
          true
        end

        private

        def start_create(chat_id, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          unless user
            Telegram::Api.answer_callback(cb_id, t.(:no_linked_account)) rescue nil
            return
          end

          Telegram::Api.answer_callback(cb_id, t.(:create_tournament_reply)) rescue nil

          Telegram::Helpers::Conversation.start(chat_id, {
            "flow" => "create_tournament",
            "step" => "entry",
            "fields" => {},
            "message_id" => message_id
          })

          send_start_options(chat_id, message_id: message_id)
        end

        def send_start_options(chat_id, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          text = t.(:create_tournament_start_options)
          buttons = [
            [ { text: locale == "ru" ? "Создать в боте" : "Create in bot", callback_data: "tournament:create:bot" } ],
            [ { text: locale == "ru" ? "Создать на сайте" : "Create on website", url: "https://getcourt.co/tournaments/new" } ],
            [ { text: t.(:cancel_btn), callback_data: "tournament:create:cancel" } ]
          ]
          send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
        end

        def step_number(step)
          STEPS.index(step).to_i + 1
        end

        def send_step_prompt(chat_id, step, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          header = t.(:create_tournament_step, step: step_number(step), total: TOTAL_STEPS)
          cancel_row = [ { text: t.(:cancel_btn), callback_data: "tournament:create:cancel" } ]

          case step
          when "name"
            text = build_step_text(chat_id, header, t.(:create_tournament_name))
            buttons = [ cancel_row ]
            send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)

          when "players_count"
            text = build_step_text(chat_id, header, t.(:create_tournament_players))
            row = [ 2, 4, 8, 16 ].map { |n| { text: n.to_s, callback_data: "tournament:create:players:#{n}" } }
            other_text = locale == "ru" ? "Другое количество" : "Other amount"
            buttons = [ row, [ { text: other_text, callback_data: "tournament:create:players:other" } ], cancel_row ]
            send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)

          when "games_count"
            text = build_step_text(chat_id, header, t.(:create_tournament_games_count))
            row = [ 3, 5, 7 ].map { |n| { text: n.to_s, callback_data: "tournament:create:games_count:#{n}" } }
            unknown_text = locale == "ru" ? "Неизвестно" : "Unknown"
            buttons = [ row, [ { text: unknown_text, callback_data: "tournament:create:skip" } ], cancel_row ]
            send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)

          when "format"
            text = build_step_text(chat_id, header, t.(:create_tournament_format))
            buttons = [
              [
                { text: "Singles", callback_data: "tournament:create:format:singles" },
                { text: "Doubles", callback_data: "tournament:create:format:doubles" }
              ],
              [ { text: t.(:skip_btn), callback_data: "tournament:create:skip" } ],
              cancel_row
            ]
            send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)

          when "court"
            send_court_selection(chat_id, 1, message_id: message_id)

          when "start_date"
            text = build_step_text(chat_id, header, t.(:create_tournament_date))
            buttons = [ [ { text: t.(:skip_btn), callback_data: "tournament:create:skip" } ], cancel_row ]
            send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)

          when "start_time"
            text = build_step_text(chat_id, header, t.(:create_tournament_time))
            buttons = [ [ { text: t.(:skip_btn), callback_data: "tournament:create:skip" } ], cancel_row ]
            send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
          end
        end

        def send_court_selection(chat_id, page, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          user = Telegram::Helpers::UserLookup.find_user(chat_id)

          user_city = normalized_city(user&.city_name)
          courts = Court.visible_to(user).to_a.sort_by do |court|
            same_city_rank = if user_city && normalized_city(court.city_name) == user_city
              0
            else
              1
            end
            [ same_city_rank, court.name.to_s.downcase ]
          end
          per_page = 5
          total_pages = [ (courts.size.to_f / per_page).ceil, 1 ].max
          page = [ [ page, 1 ].max, total_pages ].min
          offset = (page - 1) * per_page
          slice = courts.slice(offset, per_page) || []

          step_num = step_number("court")
          header = t.(:create_tournament_step, step: step_num, total: TOTAL_STEPS)
          text = build_step_text(chat_id, header, t.(:create_tournament_court))
          cancel_row = [ { text: t.(:cancel_btn), callback_data: "tournament:create:cancel" } ]

          buttons = slice.map { |c| [ { text: c.name, callback_data: "tournament:create:court:#{c.id}" } ] }

          nav = []
          nav << { text: t.(:prev_page), callback_data: "tournament:create:court_page:#{page - 1}" } if page > 1
          nav << { text: t.(:next_page), callback_data: "tournament:create:court_page:#{page + 1}" } if page < total_pages
          buttons << nav unless nav.empty?
          buttons << [ { text: t.(:create_court), callback_data: "tournament:create:court_new" } ]
          buttons << [ { text: t.(:skip_btn), callback_data: "tournament:create:skip" } ]
          buttons << cancel_row

          send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
        end

        def normalized_city(value)
          city = ::I18n.transliterate(value.to_s).downcase.strip
          city = city.gsub(/\s+/, " ")
          return nil if city.blank?

          # Handle common transliteration variant: Yekaterinburg vs Ekaterinburg.
          city.sub(/\Ay(?=[aeiou])/, "")
        end

        def send_players_count_input_prompt(chat_id, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          header = t.(:create_tournament_step, step: step_number("players_count"), total: TOTAL_STEPS)
          prompt = locale == "ru" ? "Введите количество участников:" : "Enter participants count:"
          text = build_step_text(chat_id, header, prompt)
          buttons = [ [ { text: t.(:cancel_btn), callback_data: "tournament:create:cancel" } ] ]
          send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
        end

        def handle_skip(chat_id, message_id = nil)
          conv = Telegram::Helpers::Conversation.get(chat_id)
          step = conv["step"]
          # Can skip: games_count, format, court, start_date, start_time (not name or players_count)
          skippable = %w[games_count format court start_date start_time]
          if skippable.include?(step)
            save_and_advance(chat_id, conv, step, message_id: message_id || conv["message_id"])
          end
        end

        def save_and_advance(chat_id, conv, current_step, message_id: nil)
          idx = STEPS.index(current_step)
          next_step = idx ? STEPS[idx + 1] : nil

          if next_step
            conv["step"] = next_step
            conv["message_id"] = message_id if message_id
            Telegram::Helpers::Conversation.set(chat_id, conv)
            send_step_prompt(chat_id, next_step, message_id: conv["message_id"])
          else
            finalize_tournament(chat_id, conv)
          end
        end

        def finalize_tournament(chat_id, conv)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          fields = conv["fields"] || {}
          message_id = conv["message_id"]

          Telegram::Helpers::Conversation.finish(chat_id)

          tournament = Tournament.new(
            user_id: user.id,
            name: fields["name"],
            players_count: fields["players_count"] || 4,
            games_count: fields["games_count"],
            format: fields["format"],
            start_date: fields["start_date"],
            time: fields["start_time"]
          )

          # Link court if provided
          if fields["court_id"].present?
            tournament.court_ids = [ fields["court_id"] ]
          end

          if tournament.save
            Telegram::Handlers::TournamentsHandler.show_tournament(chat_id, tournament.id, 1, message_id: message_id) rescue nil
          else
            send_or_edit_text(chat_id, t.(:create_tournament_error, error: tournament.errors.full_messages.join(", ")), message_id: message_id)
            Telegram::Handlers::MenuHandler.menu(chat_id, message_id: message_id)
          end
        rescue => e
          Rails.logger.error "[TournamentsFlow] finalize_tournament error: #{e.class} #{e.message}"
          t = ->(key, **args) { Telegram::I18n.t(key, locale: "ru", **args) }
          send_or_edit_text(chat_id, t.(:create_tournament_error, error: e.message), message_id: message_id) rescue nil
        end

        def handle_join(chat_id, tournament_id, page, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          tournament = Tournament.find_by(id: tournament_id)

          unless user && tournament
            Telegram::Api.answer_callback(cb_id, t.(:tournament_not_found), show_alert: true) rescue nil
            return
          end

          tournament.with_lock do
            if tournament.tournament_participants.exists?(user_id: user.id)
              Telegram::Api.answer_callback(cb_id, t.(:tournament_already_joined), show_alert: false) rescue nil
            elsif tournament.players_count.to_i.positive? && tournament.tournament_participants.count >= tournament.players_count
              full_text = locale == "ru" ? "Турнир уже заполнен" : "Tournament is full"
              Telegram::Api.answer_callback(cb_id, full_text, show_alert: false) rescue nil
            else
              tournament.tournament_participants.create!(user: user, name: user.name.presence || user.email)
              Telegram::Api.answer_callback(cb_id, t.(:tournament_joined), show_alert: false) rescue nil
            end
          end

          Telegram::Handlers::TournamentsHandler.show_tournament(chat_id, tournament_id, page, message_id: message_id)
        rescue => e
          Rails.logger.error "[TournamentsFlow] handle_join error: #{e.class} #{e.message}"
        end

        def handle_leave(chat_id, tournament_id, page, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          tournament = Tournament.find_by(id: tournament_id)

          unless user && tournament
            Telegram::Api.answer_callback(cb_id, t.(:tournament_not_found), show_alert: true) rescue nil
            return
          end

          tp = tournament.tournament_participants.find_by(user_id: user.id)
          tp&.destroy
          Telegram::Api.answer_callback(cb_id, t.(:tournament_left), show_alert: false) rescue nil

          Telegram::Handlers::TournamentsHandler.show_tournament(chat_id, tournament_id, page, message_id: message_id)
        rescue => e
          Rails.logger.error "[TournamentsFlow] handle_leave error: #{e.class} #{e.message}"
        end

        def build_step_text(chat_id, header, prompt)
          summary = entered_fields_text(chat_id)
          return "#{header}\n\n#{prompt}" if summary.blank?
          "#{header}\n\n#{summary}\n\n#{prompt}"
        end

        def entered_fields_text(chat_id)
          conv = Telegram::Helpers::Conversation.get(chat_id)
          fields = conv["fields"] || {}
          return nil if fields.empty?

          locale = Telegram::Helpers::UserLookup.locale_for(chat_id).to_s
          labels = if locale == "ru"
            { "name" => "Название", "players_count" => "Участники", "games_count" => "Игры",
              "format" => "Формат", "court_id" => "Корт", "start_date" => "Дата начала", "start_time" => "Время начала" }
          else
            { "name" => "Name", "players_count" => "Players", "games_count" => "Games",
              "format" => "Format", "court_id" => "Court", "start_date" => "Start date", "start_time" => "Start time" }
          end

          lines = []
          lines << "#{labels["name"]}: #{fields["name"]}" if fields["name"].present?
          lines << "#{labels["players_count"]}: #{fields["players_count"]}" if fields["players_count"].present?
          lines << "#{labels["games_count"]}: #{fields["games_count"]}" if fields["games_count"].present?
          lines << "#{labels["format"]}: #{fields["format"]}" if fields["format"].present?
          if fields["court_id"].present?
            court_name = Court.where(id: fields["court_id"]).pick(:name)
            lines << "#{labels["court_id"]}: #{court_name.presence || fields["court_id"]}"
          end
          lines << "#{labels["start_date"]}: #{fields["start_date"]}" if fields["start_date"].present?
          lines << "#{labels["start_time"]}: #{fields["start_time"]}" if fields["start_time"].present?
          return nil if lines.empty?

          title = locale == "ru" ? "Введено:" : "Entered:"
          ([ title ] + lines).join("\n")
        end

        def delete_input_message(message)
          chat_id = (message.dig("chat", "id") || message.dig("from", "id"))
          message_id = message["message_id"]
          return unless chat_id && message_id
          Telegram::Api.delete_message(chat_id, message_id) rescue nil
        end

        def send_or_edit_with_buttons(chat_id, text, buttons, message_id: nil)
          resp = nil
          if message_id
            resp = Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons) rescue nil
          end
          if resp.nil? || (resp.is_a?(Hash) && resp["ok"] == false)
            resp = Telegram::Api.send_with_buttons(chat_id, text, buttons)
          end

          new_message_id = resp.is_a?(Hash) ? resp.dig("result", "message_id") : nil
          return unless new_message_id

          conv = Telegram::Helpers::Conversation.get(chat_id)
          return unless %w[create_tournament tournament_add_result tournament_invite].include?(conv["flow"])
          conv["message_id"] = new_message_id
          Telegram::Helpers::Conversation.set(chat_id, conv)
        end

        def send_or_edit_text(chat_id, text, message_id: nil)
          if message_id
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, []) rescue nil
          else
            Telegram::Api.send_simple(chat_id, text)
          end
        end

        def start_add_result(chat_id, tournament_id, page, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          tournament = Tournament.find_by(id: tournament_id)

          unless user && tournament
            Telegram::Api.answer_callback(cb_id, t.(:tournament_not_found), show_alert: true) rescue nil
            return
          end

          if tournament.user_id != user.id
            Telegram::Api.answer_callback(cb_id, t.(:no_permission), show_alert: true) rescue nil
            return
          end

          unless tournament.started?
            Telegram::Api.answer_callback(cb_id, t.(:tournament_results_locked), show_alert: false) rescue nil
            return
          end

          Telegram::Api.answer_callback(cb_id, "") rescue nil
          Telegram::Helpers::Conversation.start(chat_id, {
            "flow" => "tournament_add_result",
            "step" => "participant",
            "tournament_id" => tournament.id,
            "page" => page.to_i,
            "message_id" => message_id,
            "fields" => {}
          })

          send_add_result_prompt(chat_id, message_id: message_id)
        end

        def handle_add_result_user(chat_id, conv, user_id, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          return unless conv["flow"] == "tournament_add_result" && conv["step"] == "participant"

          tournament = Tournament.find_by(id: conv["tournament_id"])
          participant = tournament&.tournament_participants&.includes(:user)&.find_by(user_id: user_id)
          unless participant&.user
            Telegram::Api.answer_callback(cb_id, t.(:user_not_found), show_alert: false) rescue nil
            return
          end

          Telegram::Api.answer_callback(cb_id, "") rescue nil
          conv["fields"] ||= {}
          conv["fields"]["user_id"] = participant.user_id
          conv["fields"]["user_name"] = participant.name.presence || participant.user.name.presence || participant.user.email
          conv["step"] = "score"
          Telegram::Helpers::Conversation.set(chat_id, conv)
          send_add_result_prompt(chat_id, message_id: conv["message_id"] || message_id)
        end

        def handle_add_result_skip_hours(chat_id, conv, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          return unless conv["flow"] == "tournament_add_result" && conv["step"] == "hours"

          Telegram::Api.answer_callback(cb_id, "") rescue nil
          conv["fields"] ||= {}
          conv["fields"]["hours"] = nil
          save_add_result(chat_id, conv, t)
        end

        def cancel_add_result(chat_id, conv, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          return unless conv["flow"] == "tournament_add_result"

          Telegram::Api.answer_callback(cb_id, t.(:tournament_add_result_cancelled), show_alert: false) rescue nil
          Telegram::Helpers::Conversation.finish(chat_id)
          tournament_id = conv["tournament_id"]
          page = conv["page"].to_i
          Telegram::Handlers::TournamentsHandler.show_tournament(chat_id, tournament_id, page, message_id: conv["message_id"] || message_id)
        end

        def process_add_result_text(chat_id, conv, step, text, t)
          case step
          when "score"
            if text.blank?
              Telegram::Api.send_simple(chat_id, t.(:tournament_add_result_score_invalid))
              return
            end

            conv["fields"] ||= {}
            conv["fields"]["score"] = text
            conv["step"] = "hours"
            Telegram::Helpers::Conversation.set(chat_id, conv)
            send_add_result_prompt(chat_id, message_id: conv["message_id"])

          when "hours"
            hours = parse_hours_input(text)
            unless hours
              Telegram::Api.send_simple(chat_id, t.(:tournament_add_result_hours_invalid))
              return
            end

            conv["fields"] ||= {}
            conv["fields"]["hours"] = hours
            save_add_result(chat_id, conv, t)

          else
            Telegram::Api.send_simple(chat_id, t.(:please_use_buttons))
          end
        end

        def send_add_result_prompt(chat_id, message_id: nil)
          conv = Telegram::Helpers::Conversation.get(chat_id)
          return unless conv["flow"] == "tournament_add_result"

          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          tournament = Tournament.find_by(id: conv["tournament_id"])
          title = tournament&.name.presence || "Tournament ##{conv["tournament_id"]}"
          fields = conv["fields"] || {}

          base = t.(:tournament_add_result_title, title: title)
          entered = []
          entered << "#{locale == "ru" ? "Игрок" : "Player"}: #{fields["user_name"]}" if fields["user_name"].present?
          entered << t.(:tournament_add_result_score_line, score: fields["score"]) if fields["score"].present?
          text = entered.any? ? "#{base}\n\n#{entered.join("\n")}" : base

          buttons = []
          if conv["step"] == "participant"
            text = "#{text}\n\n#{locale == "ru" ? "Выберите участника:" : "Select participant:"}"
            tournament&.tournament_participants&.includes(:user)&.each do |participant|
              next unless participant.user
              name = participant.name.presence || participant.user.name.presence || participant.user.email
              buttons << [ { text: name, callback_data: "tournament:add_result:user:#{participant.user_id}" } ]
            end
          elsif conv["step"] == "score"
            text = "#{text}\n\n#{t.(:tournament_add_result_enter_score)}"
          elsif conv["step"] == "hours"
            text = "#{text}\n\n#{t.(:tournament_add_result_enter_hours)}"
            unknown_text = locale == "ru" ? "Неизвестно" : "Unknown"
            buttons << [ { text: unknown_text, callback_data: "tournament:add_result:skip_hours" } ]
          end
          buttons << [ { text: t.(:cancel_btn), callback_data: "tournament:add_result:cancel" } ]

          send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id || conv["message_id"])
        end

        def save_add_result(chat_id, conv, t)
          tournament = Tournament.find_by(id: conv["tournament_id"])
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          return unless tournament && user

          fields = conv["fields"] || {}
          result_user = tournament.tournament_participants.includes(:user).find_by(user_id: fields["user_id"])&.user
          unless result_user
            Telegram::Api.send_simple(chat_id, t.(:user_not_found))
            return
          end
          score = fields["score"].to_s.strip
          hours = fields["hours"]
          create_tournament_result!(tournament, user, result_user, score: score, hours: hours)

          Telegram::Helpers::Conversation.finish(chat_id)
          Telegram::Api.send_simple(chat_id, t.(:tournament_add_result_saved))
          Telegram::Handlers::TournamentsHandler.show_tournament(chat_id, tournament.id, conv["page"].to_i, message_id: conv["message_id"])
        rescue => e
          Rails.logger.error "[TournamentsFlow] save_add_result error: #{e.class} #{e.message}"
          Telegram::Api.send_simple(chat_id, t.(:create_tournament_error, error: e.message)) rescue nil
        end

        def create_tournament_result!(tournament, actor, result_user, score:, hours:)
          court = tournament.courts.first || Court.first
          raise "Court not found" unless court

          ActiveRecord::Base.transaction do
            game = Game.create!(
              tournament: tournament,
              court: court,
              user: actor,
              date: tournament.start_date || Date.current,
              sport: "tennis"
            )

            Match.create!(
              game: game,
              user: result_user,
              score: score,
              mode: tournament.format.presence || "singles",
              outcome: "draw",
              played_at: Time.current
            )

            next if hours.nil?

            hours_key = tournament.format == "doubles" ? "doubles_hours" : "singles_hours"
            PlayerStatisticEntry.create!(
              user: result_user,
              game: game,
              actor: actor,
              data: { hours_key => hours },
              source: "telegram",
              recorded_at: Time.current
            )
          end
        end

        def start_invite(chat_id, tournament_id, page, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          tournament = Tournament.find_by(id: tournament_id)

          unless user && tournament
            Telegram::Api.answer_callback(cb_id, t.(:tournament_not_found), show_alert: true) rescue nil
            return
          end

          if tournament.user_id != user.id
            Telegram::Api.answer_callback(cb_id, t.(:no_permission), show_alert: true) rescue nil
            return
          end

          Telegram::Api.answer_callback(cb_id, "") rescue nil
          Telegram::Helpers::Conversation.start(chat_id, {
            "flow" => "tournament_invite",
            "step" => "handles",
            "tournament_id" => tournament.id,
            "page" => page.to_i,
            "message_id" => message_id
          })

          buttons = [ [ { text: t.(:cancel_btn), callback_data: "tournament:invite_cancel:#{tournament.id}:#{page}" } ] ]
          send_or_edit_with_buttons(chat_id, t.(:tournament_invite_prompt), buttons, message_id: message_id)
        end

        def cancel_invite(chat_id, tournament_id, page, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          Telegram::Api.answer_callback(cb_id, t.(:tournament_invite_cancelled), show_alert: false) rescue nil
          conv = Telegram::Helpers::Conversation.get(chat_id)
          Telegram::Helpers::Conversation.finish(chat_id) if conv["flow"] == "tournament_invite"
          Telegram::Handlers::TournamentsHandler.show_tournament(chat_id, tournament_id, page, message_id: message_id || conv["message_id"])
        end

        def handle_invite_decline(chat_id, tournament_id, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          tournament = Tournament.find_by(id: tournament_id)
          decliner = Telegram::Helpers::UserLookup.find_user(chat_id)

          Telegram::Api.answer_callback(cb_id, t.(:tournament_invite_declined), show_alert: false) rescue nil
          if message_id
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, t.(:tournament_invite_declined_user, id: tournament_id), []) rescue nil
          end

          owner_chat_id = tournament&.user&.telegram_chat_id
          return unless owner_chat_id.present?

          name = decliner&.name.presence || decliner&.telegram_username.presence || "User"
          Telegram::Api.send_simple(owner_chat_id.to_s, t.(:tournament_invite_declined_owner, name: name, id: tournament_id)) rescue nil
        end

        def process_invite_text(chat_id, conv, text, t)
          return unless conv["flow"] == "tournament_invite"
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id).to_s

          tournament = Tournament.find_by(id: conv["tournament_id"])
          inviter = Telegram::Helpers::UserLookup.find_user(chat_id)
          unless tournament && inviter && (inviter.admin? || tournament.user_id == inviter.id)
            Telegram::Helpers::Conversation.finish(chat_id)
            Telegram::Api.send_simple(chat_id, t.(:no_permission))
            return
          end

          handles = text.scan(/@[\w\d_]+/i).map { |h| h.delete_prefix("@").downcase }.uniq
          if handles.empty?
            Telegram::Api.send_simple(chat_id, t.(:tournament_invite_handles_invalid))
            return
          end

          resolved = resolve_users_by_handles(handles)
          not_found = []
          skipped_self = []
          no_telegram = []
          failed_send = []
          sent_count = 0

          resolved.each do |handle, user|
            if user.nil?
              not_found << "@#{handle}"
              next
            end

            if user.id == inviter.id
              skipped_self << "@#{handle}"
              next
            end

            unless user.telegram_chat_id.present?
              no_telegram << "@#{handle}"
              next
            end

            host = ENV.fetch("APP_HOST", "https://getcourt.co")
            tournament_url = "#{host}/tournaments/#{tournament.id}"
            title = tournament.name.presence || "Tournament ##{tournament.id}"
            join_text = locale.to_s == "ru" ? "Принять" : "Join"
            decline_text = locale.to_s == "ru" ? "Отклонить" : "Decline"

            begin
              resp = Telegram::Api.send_with_buttons(
                user.telegram_chat_id.to_s,
                t.(:tournament_invite_message, title: title, id: tournament.id, url: tournament_url),
                [
                  [ { text: join_text, callback_data: "tournament:join:#{tournament.id}:1" },
                    { text: decline_text, callback_data: "tournament:invite_decline:#{tournament.id}" } ]
                ]
              )
              if !resp.is_a?(Hash) || resp["ok"] != false
                sent_count += 1
              else
                failed_send << "@#{handle}"
              end
            rescue
              failed_send << "@#{handle}"
            end
          end

          Telegram::Helpers::Conversation.finish(chat_id)
          parts = []
          parts << t.(:tournament_invite_sent) if sent_count.positive?
          parts << t.(:tournament_invite_not_found, users: not_found.join(", ")) if not_found.any?
          parts << t.(:tournament_invite_skipped_self, users: skipped_self.join(", ")) if skipped_self.any?
          if no_telegram.any?
            no_tg_text = locale.to_s == "ru" ? "Без Telegram: #{no_telegram.join(", ")}" : "No Telegram chat linked: #{no_telegram.join(", ")}"
            parts << no_tg_text
          end
          if failed_send.any?
            failed_send_text = locale.to_s == "ru" ? "Не удалось отправить: #{failed_send.join(", ")}" : "Failed to send: #{failed_send.join(", ")}"
            parts << failed_send_text
          end
          if parts.empty?
            nothing_sent_text = locale.to_s == "ru" ? "Приглашения не отправлены." : "No invitations were sent."
            parts << nothing_sent_text
          end
          Telegram::Api.send_simple(chat_id, parts.join("\n")) rescue nil

          Telegram::Handlers::TournamentsHandler.show_tournament(chat_id, tournament.id, conv["page"].to_i, message_id: conv["message_id"])
        rescue => e
          Rails.logger.error "[TournamentsFlow] process_invite_text error: #{e.class} #{e.message}"
          Telegram::Api.send_simple(chat_id, t.(:create_tournament_error, error: e.message)) rescue nil
        end

        def resolve_users_by_handles(handles)
          map = {}
          cols = User.column_names
          uname_cols = []
          uname_cols << "telegram_username" if cols.include?("telegram_username")
          uname_cols << "username" if cols.include?("username")

          by_username = {}
          if uname_cols.any?
            conds = uname_cols.map { |c| "LOWER(#{c}) IN (:hs)" }.join(" OR ")
            User.where(conds, hs: handles).find_each do |u|
              uname_cols.each do |c|
                v = u.public_send(c).to_s.downcase
                by_username[v] = u if v.present?
              end
            end
          end

          handles.each do |h|
            map[h] = by_username[h]
          end
          map
        end

        def parse_time_input(text)
          value = text.to_s.strip
          return nil unless value.match?(/\A\d{1,2}:\d{2}\z/)

          hh, mm = value.split(":").map(&:to_i)
          return nil if hh > 23 || mm > 59

          Time.zone.local(2000, 1, 1, hh, mm, 0)
        rescue
          nil
        end

        def parse_hours_input(text)
          value = Float(text)
          return nil if value.negative?

          value
        rescue
          nil
        end
      end
    end
  end
end
