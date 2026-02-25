module Telegram
  module Flows
    class TournamentsFlow
      # Step-by-step tournament creation + join/leave/show callbacks
      #
      # Steps: name, players_count, tournament_type, games_count, format, court, start_date, start_time
      # Conversation state stored via Telegram::Helpers::Conversation with flow: "create_tournament"

      STEPS = %w[name players_count tournament_type games_count format court start_date start_time].freeze
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

          when /\Atournament:create:type:(bracket|round_robin)\z/
            type = $1
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            conv = Telegram::Helpers::Conversation.get(cb.chat_id)
            conv["fields"] ||= {}
            conv["fields"]["tournament_type"] = type
            save_and_advance(cb.chat_id, conv, "tournament_type", message_id: conv["message_id"] || cb.message_id)

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

          when /\Atournament:join_invited:(\d+)(?::(\d+))?\z/
            tid = $1.to_i
            page = ($2 || 1).to_i
            handle_join(cb.chat_id, tid, page, cb_id: cb.cb_id, message_id: cb.message_id, invited: true)

          when /\Atournament:join_pending:(\d+)(?::(\d+))?\z/
            Telegram::Api.answer_callback(cb.cb_id, t.(:tournament_join_pending), show_alert: false) rescue nil

          when /\Atournament:approve_participation:(\d+)\z/
            pid = $1.to_i
            handle_approve_participation(cb.chat_id, pid, cb_id: cb.cb_id, message_id: cb.message_id)

          when /\Atournament:reject_participation:(\d+)\z/
            pid = $1.to_i
            handle_reject_participation(cb.chat_id, pid, cb_id: cb.cb_id, message_id: cb.message_id)

          when /\Atournament:manage:(\d+)(?::(\d+))?\z/
            tid = $1.to_i
            page = ($2 || 1).to_i
            handle_manage_players(cb.chat_id, tid, page, cb_id: cb.cb_id, message_id: cb.message_id)

          when /\Atournament:edit:(\d+)(?::(\d+))?\z/
            tid = $1.to_i
            page = ($2 || 1).to_i
            start_edit(cb.chat_id, tid, page, cb_id: cb.cb_id, message_id: cb.message_id)

          when /\Atournament:edit:field:(name|start_date|time)\z/
            field = $1
            handle_edit_field(cb.chat_id, field, cb_id: cb.cb_id, message_id: cb.message_id)

          when /\Atournament:edit:skip\z/
            handle_edit_skip(cb.chat_id, cb_id: cb.cb_id, message_id: cb.message_id)

          when /\Atournament:edit:cancel\z/
            cancel_edit(cb.chat_id, cb_id: cb.cb_id, message_id: cb.message_id)

          when /\Atournament:delete:(\d+)(?::(\d+))?\z/
            tid = $1.to_i
            page = ($2 || 1).to_i
            prompt_delete(cb.chat_id, tid, page, cb_id: cb.cb_id, message_id: cb.message_id)

          when /\Atournament:delete:confirm:(\d+)(?::(\d+))?\z/
            tid = $1.to_i
            page = ($2 || 1).to_i
            confirm_delete(cb.chat_id, tid, page, cb_id: cb.cb_id, message_id: cb.message_id)

          when /\Atournament:delete:cancel:(\d+)(?::(\d+))?\z/
            tid = $1.to_i
            page = ($2 || 1).to_i
            cancel_delete(cb.chat_id, tid, page, cb_id: cb.cb_id, message_id: cb.message_id)

          when /\Atournament:rr_add_match:(\d+)(?::(\d+))?\z/
            tid = $1.to_i
            page = ($2 || 1).to_i
            start_round_robin_add_match(cb.chat_id, tid, page, cb_id: cb.cb_id, message_id: cb.message_id)

          when /\Atournament:rr_pick_a:(\d+):(\d+)\z/
            rr_pick_a(cb.chat_id, $1.to_i, $2.to_i, cb_id: cb.cb_id, message_id: cb.message_id)

          when /\Atournament:rr_pick_a2:(\d+):(\d+)\z/
            rr_pick_a2(cb.chat_id, $1.to_i, $2.to_i, cb_id: cb.cb_id, message_id: cb.message_id)

          when /\Atournament:rr_pick_b:(\d+):(\d+)\z/
            rr_pick_b(cb.chat_id, $1.to_i, $2.to_i, cb_id: cb.cb_id, message_id: cb.message_id)

          when /\Atournament:rr_pick_b2:(\d+):(\d+)\z/
            rr_pick_b2(cb.chat_id, $1.to_i, $2.to_i, cb_id: cb.cb_id, message_id: cb.message_id)

          when /\Atournament:rr_cancel\z/
            rr_cancel(cb.chat_id, cb_id: cb.cb_id, message_id: cb.message_id)

          when /\Atournament:rr_standings:(\d+)(?::(\d+))?\z/
            tid = $1.to_i
            page = ($2 || 1).to_i
            show_round_robin_standings(cb.chat_id, tid, page, cb_id: cb.cb_id, message_id: cb.message_id)

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
          return false unless %w[create_tournament tournament_invite tournament_edit tournament_rr_add_match].include?(flow)

          delete_input_message(message)

          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          step = conv["step"]

          if flow == "tournament_invite"
            process_invite_text(chat_id, conv, text, t)
            return true
          end

          if flow == "tournament_edit"
            process_edit_text(chat_id, conv, step, text, t)
            return true
          end

          if flow == "tournament_rr_add_match"
            process_round_robin_add_match_text(chat_id, conv, step, text, t)
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

          when "tournament_type"
            val = text.to_s.strip.downcase
            val = "round_robin" if %w[rr roundrobin round_robin].include?(val)
            val = "bracket" unless %w[bracket round_robin].include?(val)
            conv["fields"] ||= {}
            conv["fields"]["tournament_type"] = val
            save_and_advance(chat_id, conv, "tournament_type", message_id: conv["message_id"])

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

          when "tournament_type"
            text = build_step_text(chat_id, header, t.(:create_tournament_type))
            buttons = [
              [ { text: t.(:tournament_type_bracket), callback_data: "tournament:create:type:bracket" } ],
              [ { text: t.(:tournament_type_round_robin), callback_data: "tournament:create:type:round_robin" } ],
              [ { text: t.(:skip_btn), callback_data: "tournament:create:skip" } ],
              cancel_row
            ]
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
          # Can skip: tournament_type, games_count, format, court, start_date, start_time (not name or players_count)
          skippable = %w[tournament_type games_count format court start_date start_time]
          if step == "tournament_type"
            conv["fields"] ||= {}
            conv["fields"]["tournament_type"] = "bracket"
            Telegram::Helpers::Conversation.set(chat_id, conv)
          end
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
            tournament_type: fields["tournament_type"].presence || "bracket",
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

        def handle_join(chat_id, tournament_id, page, cb_id: nil, message_id: nil, invited: false)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          tournament = Tournament.find_by(id: tournament_id)

          unless user && tournament
            Telegram::Api.answer_callback(cb_id, t.(:tournament_not_found), show_alert: true) rescue nil
            return
          end

          callback_text = nil
          notify_owner_payload = nil

          tournament.with_lock do
            participation = tournament.tournament_participants.find_by(user_id: user.id)
            direct_join = invited || user.admin? || user.id == tournament.user_id

            approved_count = approved_participants_scope(tournament).count
            full = tournament.players_count.to_i.positive? && approved_count >= tournament.players_count

            if participation
              if participation.pending?
                if direct_join
                  if full
                    callback_text = t.(:tournament_full)
                  else
                    participation.update(status: "approved", approved_at: Time.current) rescue nil
                    callback_text = invited ? t.(:tournament_invitation_accepted) : t.(:tournament_joined)
                  end
                else
                  callback_text = t.(:tournament_request_already_sent)
                end
              else
                callback_text = t.(:tournament_already_joined)
              end
            else
              if full
                callback_text = t.(:tournament_full)
              elsif direct_join
                tournament.tournament_participants.create!(user: user, name: user.name.presence || user.email, status: "approved", approved_at: Time.current)
                callback_text = invited ? t.(:tournament_invitation_accepted) : t.(:tournament_joined)
              else
                participation = tournament.tournament_participants.create!(user: user, name: user.name.presence || user.email, status: "pending")
                callback_text = t.(:tournament_join_request_sent)

                owner_chat_id = tournament.user&.telegram_chat_id
                if owner_chat_id.present?
                  requester = Telegram::Helpers::UserLookup.display_name(user)
                  host = ENV.fetch("APP_HOST", "https://getcourt.co")
                  owner_locale = Telegram::Helpers::UserLookup.locale_for(owner_chat_id.to_s)
                  owner_t = ->(key, **args) { Telegram::I18n.t(key, locale: owner_locale, **args) }
                  notify_owner_payload = {
                    chat_id: owner_chat_id,
                    text: owner_t.(:tournament_join_request_owner_text, id: tournament.id, name: requester, url: "#{host}/tournaments/#{tournament.id}"),
                    participation_id: participation.id
                  }
                end
              end
            end
          end

          Telegram::Api.answer_callback(cb_id, callback_text, show_alert: false) rescue nil
          if notify_owner_payload
            buttons = [ [
              { text: "Approve", callback_data: "tournament:approve_participation:#{notify_owner_payload[:participation_id]}" },
              { text: "Reject",  callback_data: "tournament:reject_participation:#{notify_owner_payload[:participation_id]}" }
            ] ]
            Telegram::Api.send_api("sendMessage", {
              chat_id: notify_owner_payload[:chat_id],
              text: notify_owner_payload[:text],
              reply_markup: { inline_keyboard: buttons }
            }) rescue nil
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

        def handle_approve_participation(chat_id, participation_id, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          participation = TournamentParticipant.find_by(id: participation_id)

          unless participation && user
            Telegram::Api.answer_callback(cb_id, t.(:tournament_request_not_found), show_alert: false) rescue nil
            return
          end

          tournament = participation.tournament
          unless user.admin? || user.id == tournament.user_id
            Telegram::Api.answer_callback(cb_id, t.(:no_permission), show_alert: true) rescue nil
            return
          end

          callback_text = nil
          approved = false
          tournament.with_lock do
            approved_count = approved_participants_scope(tournament).count
            full = tournament.players_count.to_i.positive? && approved_count >= tournament.players_count

            if participation.approved?
              callback_text = t.(:tournament_already_approved)
            elsif full
              callback_text = t.(:tournament_full)
            else
              participation.update(status: "approved", approved_at: Time.current) rescue nil
              callback_text = t.(:tournament_participation_approved)
              approved = true
            end
          end

          Telegram::Api.answer_callback(cb_id, callback_text, show_alert: false) rescue nil
          return unless approved

          if chat_id && message_id
            Telegram::Api.send_api("editMessageText", {
              chat_id: chat_id,
              message_id: message_id,
              text: t.(:tournament_user_accepted),
              reply_markup: { inline_keyboard: [] }
            }) rescue nil
          end

          if participation.user&.telegram_chat_id.present?
            participant_locale = Telegram::Helpers::UserLookup.locale_for(participation.user.telegram_chat_id)
            participant_t = ->(key, **args) { Telegram::I18n.t(key, locale: participant_locale, **args) }
            Telegram::Api.send_simple(participation.user.telegram_chat_id, participant_t.(:tournament_request_approved_user, id: tournament.id)) rescue nil
          end
        rescue => e
          Rails.logger.error "[TournamentsFlow] handle_approve_participation error: #{e.class} #{e.message}"
        end

        def handle_reject_participation(chat_id, participation_id, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          participation = TournamentParticipant.find_by(id: participation_id)

          unless participation && user
            Telegram::Api.answer_callback(cb_id, t.(:tournament_request_not_found), show_alert: false) rescue nil
            return
          end

          tournament = participation.tournament
          unless user.admin? || user.id == tournament.user_id
            Telegram::Api.answer_callback(cb_id, t.(:no_permission), show_alert: true) rescue nil
            return
          end

          participation.destroy rescue nil
          Telegram::Api.answer_callback(cb_id, t.(:tournament_participation_rejected), show_alert: false) rescue nil

          if chat_id && message_id
            Telegram::Api.send_api("editMessageText", {
              chat_id: chat_id,
              message_id: message_id,
              text: t.(:tournament_user_rejected),
              reply_markup: { inline_keyboard: [] }
            }) rescue nil
          end

          if participation.user&.telegram_chat_id.present?
            participant_locale = Telegram::Helpers::UserLookup.locale_for(participation.user.telegram_chat_id)
            participant_t = ->(key, **args) { Telegram::I18n.t(key, locale: participant_locale, **args) }
            Telegram::Api.send_simple(participation.user.telegram_chat_id, participant_t.(:tournament_request_rejected_user, id: tournament.id)) rescue nil
          end
        rescue => e
          Rails.logger.error "[TournamentsFlow] handle_reject_participation error: #{e.class} #{e.message}"
        end

        def handle_manage_players(chat_id, tournament_id, page, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          tournament = Tournament.includes(tournament_participants: :user).find_by(id: tournament_id)

          unless tournament && user && (user.admin? || user.id == tournament.user_id)
            Telegram::Api.answer_callback(cb_id, t.(:no_permission), show_alert: true) rescue nil
            return
          end

          Telegram::Api.answer_callback(cb_id, "") rescue nil
          participants = tournament.tournament_participants.to_a.sort_by { |p| [ p.status == "pending" ? 0 : 1, p.created_at.to_i ] }
          lines = [ "*#{t.(:manage_players)} — ##{tournament.id}*" ]
          lines << ""
          if participants.empty?
            lines << t.(:players_list_empty)
          else
            participants.each_with_index do |p, idx|
              name = Telegram::Helpers::UserLookup.display_name(p.user, fallback: p.name.presence || "User ##{p.user_id}")
              marker = p.pending? ? "⏳" : "✅"
              lines << "#{idx + 1}. #{marker} #{name}"
            end
          end

          buttons = []
          participants.each do |p|
            next unless p.pending? || p.approved?
            name = Telegram::Helpers::UserLookup.display_name(p.user, fallback: p.name.presence || "User ##{p.user_id}")
            if p.pending?
              buttons << [ { text: "✅ #{name}", callback_data: "tournament:approve_participation:#{p.id}" } ]
            end
            buttons << [ { text: "❌ #{name}", callback_data: "tournament:reject_participation:#{p.id}" } ]
          end
          buttons << [ { text: t.(:back_to_tournament), callback_data: "tournament:show:#{tournament.id}:#{page}" } ]

          send_or_edit_with_buttons(chat_id, lines.join("\n"), buttons, message_id: message_id)
        rescue => e
          Rails.logger.error "[TournamentsFlow] handle_manage_players error: #{e.class} #{e.message}"
        end

        def start_edit(chat_id, tournament_id, page, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          tournament = Tournament.find_by(id: tournament_id)

          unless tournament && user && (user.admin? || user.id == tournament.user_id)
            Telegram::Api.answer_callback(cb_id, t.(:no_permission), show_alert: true) rescue nil
            return
          end

          Telegram::Api.answer_callback(cb_id, "") rescue nil
          Telegram::Helpers::Conversation.start(chat_id, {
            "flow" => "tournament_edit",
            "step" => "menu",
            "tournament_id" => tournament.id,
            "page" => page.to_i,
            "message_id" => message_id
          })
          render_edit_menu(chat_id)
        end

        def render_edit_menu(chat_id)
          conv = Telegram::Helpers::Conversation.get(chat_id)
          return unless conv["flow"] == "tournament_edit"

          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          buttons = [
            [ { text: t.(:tournament_edit_name), callback_data: "tournament:edit:field:name" } ],
            [ { text: t.(:tournament_edit_date), callback_data: "tournament:edit:field:start_date" } ],
            [ { text: t.(:tournament_edit_time), callback_data: "tournament:edit:field:time" } ],
            [ { text: t.(:cancel_btn), callback_data: "tournament:edit:cancel" } ]
          ]
          send_or_edit_with_buttons(chat_id, t.(:tournament_edit_prompt), buttons, message_id: conv["message_id"])
        end

        def handle_edit_field(chat_id, field, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          conv = Telegram::Helpers::Conversation.get(chat_id)
          return unless conv["flow"] == "tournament_edit"

          Telegram::Api.answer_callback(cb_id, "") rescue nil
          conv["step"] = field
          conv["message_id"] ||= message_id
          Telegram::Helpers::Conversation.set(chat_id, conv)

          key = case field
          when "name" then :create_tournament_name
          when "start_date" then :create_tournament_date
          else :create_tournament_time
          end
          buttons = [ [ { text: t.(:skip_btn), callback_data: "tournament:edit:skip" } ], [ { text: t.(:cancel_btn), callback_data: "tournament:edit:cancel" } ] ]
          send_or_edit_with_buttons(chat_id, t.(key), buttons, message_id: conv["message_id"])
        end

        def handle_edit_skip(chat_id, cb_id: nil, message_id: nil)
          conv = Telegram::Helpers::Conversation.get(chat_id)
          return unless conv["flow"] == "tournament_edit"
          Telegram::Api.answer_callback(cb_id, "") rescue nil
          conv["step"] = "menu"
          conv["message_id"] ||= message_id
          Telegram::Helpers::Conversation.set(chat_id, conv)
          render_edit_menu(chat_id)
        end

        def process_edit_text(chat_id, conv, step, text, t)
          tournament = Tournament.find_by(id: conv["tournament_id"])
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          unless tournament && user && (user.admin? || user.id == tournament.user_id)
            Telegram::Helpers::Conversation.finish(chat_id)
            Telegram::Api.send_simple(chat_id, t.(:no_permission))
            return
          end

          attrs = {}
          case step
          when "name"
            return Telegram::Api.send_simple(chat_id, t.(:create_tournament_name_invalid)) if text.blank?
            attrs[:name] = text
          when "start_date"
            date = (Date.parse(text) rescue nil)
            return Telegram::Api.send_simple(chat_id, t.(:create_tournament_date_invalid)) unless date
            attrs[:start_date] = date
          when "time"
            parsed_time = parse_time_input(text)
            return Telegram::Api.send_simple(chat_id, t.(:create_tournament_time_invalid)) unless parsed_time
            attrs[:time] = parsed_time.strftime("%H:%M")
          else
            Telegram::Api.send_simple(chat_id, t.(:please_use_buttons))
            return
          end

          if tournament.update(attrs)
            Telegram::Api.send_simple(chat_id, t.(:tournament_edit_saved)) rescue nil
            conv["step"] = "menu"
            Telegram::Helpers::Conversation.set(chat_id, conv)
            Telegram::Handlers::TournamentsHandler.show_tournament(chat_id, tournament.id, conv["page"].to_i, message_id: conv["message_id"])
          else
            Telegram::Api.send_simple(chat_id, t.(:create_tournament_error, error: tournament.errors.full_messages.join(", "))) rescue nil
          end
        end

        def cancel_edit(chat_id, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          conv = Telegram::Helpers::Conversation.get(chat_id)
          return unless conv["flow"] == "tournament_edit"

          Telegram::Api.answer_callback(cb_id, t.(:tournament_edit_cancelled), show_alert: false) rescue nil
          tournament_id = conv["tournament_id"]
          page = conv["page"].to_i
          mid = conv["message_id"] || message_id
          Telegram::Helpers::Conversation.finish(chat_id)
          Telegram::Handlers::TournamentsHandler.show_tournament(chat_id, tournament_id, page, message_id: mid)
        end

        def prompt_delete(chat_id, tournament_id, page, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          tournament = Tournament.find_by(id: tournament_id)

          unless tournament && user && (user.admin? || user.id == tournament.user_id)
            Telegram::Api.answer_callback(cb_id, t.(:no_permission), show_alert: true) rescue nil
            return
          end

          Telegram::Api.answer_callback(cb_id, "") rescue nil
          buttons = [
            [ { text: t.(:delete_tournament), callback_data: "tournament:delete:confirm:#{tournament.id}:#{page}" } ],
            [ { text: t.(:cancel_btn), callback_data: "tournament:delete:cancel:#{tournament.id}:#{page}" } ]
          ]
          send_or_edit_with_buttons(chat_id, t.(:tournament_delete_confirm), buttons, message_id: message_id)
        end

        def confirm_delete(chat_id, tournament_id, page, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          tournament = Tournament.find_by(id: tournament_id)

          unless tournament && user && (user.admin? || user.id == tournament.user_id)
            Telegram::Api.answer_callback(cb_id, t.(:no_permission), show_alert: true) rescue nil
            return
          end

          ActiveRecord::Base.transaction do
            tournament.games.update_all(tournament_id: nil)
            TournamentMatch.where(tournament_id: tournament.id).delete_all
            TournamentParticipant.where(tournament_id: tournament.id).delete_all
            TournamentCourt.where(tournament_id: tournament.id).delete_all if defined?(TournamentCourt)
            TournamentDate.where(tournament_id: tournament.id).delete_all if defined?(TournamentDate)
            tournament.destroy!
          end
          Telegram::Api.answer_callback(cb_id, t.(:tournament_deleted), show_alert: false) rescue nil
          Telegram::Handlers::TournamentsHandler.list_page(chat_id, page, message_id: message_id)
        rescue => e
          Rails.logger.error "[TournamentsFlow] confirm_delete error: #{e.class} #{e.message}"
          Telegram::Api.answer_callback(cb_id, t.(:create_tournament_error, error: e.message), show_alert: true) rescue nil
        end

        def cancel_delete(chat_id, tournament_id, page, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          Telegram::Api.answer_callback(cb_id, t.(:tournament_delete_cancelled), show_alert: false) rescue nil
          Telegram::Handlers::TournamentsHandler.show_tournament(chat_id, tournament_id, page, message_id: message_id)
        end

        def start_round_robin_add_match(chat_id, tournament_id, page, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          tournament = Tournament.find_by(id: tournament_id)
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          unless tournament && user && (user.admin? || user.id == tournament.user_id)
            Telegram::Api.answer_callback(cb_id, t.(:no_permission), show_alert: true) rescue nil
            return
          end
          unless tournament.started?
            Telegram::Api.answer_callback(cb_id, t.(:tournament_results_locked), show_alert: false) rescue nil
            return
          end

          Telegram::Api.answer_callback(cb_id, "") rescue nil
          Telegram::Helpers::Conversation.start(chat_id, {
            "flow" => "tournament_rr_add_match",
            "step" => "player_a",
            "tournament_id" => tournament.id,
            "page" => page.to_i,
            "message_id" => message_id,
            "fields" => { "team_a_ids" => [], "team_b_ids" => [] }
          })
          render_round_robin_add_match(chat_id)
        end

        def rr_pick_a(chat_id, tournament_id, user_id, cb_id: nil, message_id: nil)
          rr_pick(chat_id, tournament_id, user_id, step: "player_a", next_step_singles: "player_b", next_step_doubles: "player_a2", cb_id: cb_id, message_id: message_id)
        end

        def rr_pick_a2(chat_id, tournament_id, user_id, cb_id: nil, message_id: nil)
          rr_pick(chat_id, tournament_id, user_id, step: "player_a2", next_step_singles: "player_b", next_step_doubles: "player_b", cb_id: cb_id, message_id: message_id)
        end

        def rr_pick_b(chat_id, tournament_id, user_id, cb_id: nil, message_id: nil)
          rr_pick(chat_id, tournament_id, user_id, step: "player_b", next_step_singles: "score", next_step_doubles: "player_b2", cb_id: cb_id, message_id: message_id)
        end

        def rr_pick_b2(chat_id, tournament_id, user_id, cb_id: nil, message_id: nil)
          rr_pick(chat_id, tournament_id, user_id, step: "player_b2", next_step_singles: "score", next_step_doubles: "score", cb_id: cb_id, message_id: message_id)
        end

        def rr_pick(chat_id, tournament_id, user_id, step:, next_step_singles:, next_step_doubles:, cb_id: nil, message_id: nil)
          conv = Telegram::Helpers::Conversation.get(chat_id)
          return unless conv["flow"] == "tournament_rr_add_match" && conv["tournament_id"].to_i == tournament_id
          tournament = Tournament.find_by(id: tournament_id)
          return unless tournament
          Telegram::Api.answer_callback(cb_id, "") rescue nil

          conv["fields"] ||= {}
          conv["fields"]["team_a_ids"] ||= []
          conv["fields"]["team_b_ids"] ||= []
          used = (conv["fields"]["team_a_ids"] + conv["fields"]["team_b_ids"]).map(&:to_i)
          return if used.include?(user_id.to_i)

          if step.start_with?("player_a")
            conv["fields"]["team_a_ids"] << user_id.to_i
          else
            conv["fields"]["team_b_ids"] << user_id.to_i
          end

          doubles = tournament.format == "doubles"
          conv["step"] = doubles ? next_step_doubles : next_step_singles
          conv["message_id"] ||= message_id
          Telegram::Helpers::Conversation.set(chat_id, conv)
          render_round_robin_add_match(chat_id)
        end

        def render_round_robin_add_match(chat_id)
          conv = Telegram::Helpers::Conversation.get(chat_id)
          return unless conv["flow"] == "tournament_rr_add_match"
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          tournament = Tournament.find_by(id: conv["tournament_id"])
          return unless tournament

          participants = approved_participants_scope(tournament).includes(:user).to_a
          fields = conv["fields"] || {}
          team_a_ids = Array(fields["team_a_ids"]).map(&:to_i)
          team_b_ids = Array(fields["team_b_ids"]).map(&:to_i)
          used = (team_a_ids + team_b_ids).uniq
          buttons = []
          text = nil

          case conv["step"]
          when "player_a"
            text = t.(:tournament_rr_pick_player_a)
            participants.each do |p|
              buttons << [ { text: participant_name(p), callback_data: "tournament:rr_pick_a:#{tournament.id}:#{p.user_id}" } ]
            end
          when "player_a2"
            text = t.(:tournament_rr_pick_team_a)
            participants.each do |p|
              next if used.include?(p.user_id)
              buttons << [ { text: participant_name(p), callback_data: "tournament:rr_pick_a2:#{tournament.id}:#{p.user_id}" } ]
            end
          when "player_b"
            text = t.(:tournament_rr_pick_player_b)
            participants.each do |p|
              next if used.include?(p.user_id)
              buttons << [ { text: participant_name(p), callback_data: "tournament:rr_pick_b:#{tournament.id}:#{p.user_id}" } ]
            end
          when "player_b2"
            text = t.(:tournament_rr_pick_team_b)
            participants.each do |p|
              next if used.include?(p.user_id)
              buttons << [ { text: participant_name(p), callback_data: "tournament:rr_pick_b2:#{tournament.id}:#{p.user_id}" } ]
            end
          else
            text = t.(:tournament_rr_enter_score)
          end

          buttons << [ { text: t.(:cancel_btn), callback_data: "tournament:rr_cancel" } ]
          send_or_edit_with_buttons(chat_id, text, buttons, message_id: conv["message_id"])
        end

        def process_round_robin_add_match_text(chat_id, conv, step, text, t)
          return Telegram::Api.send_simple(chat_id, t.(:please_use_buttons)) unless step == "score"

          parsed = Telegram::Flows::StatsScore::ScoreParser.parse(text)
          unless parsed
            Telegram::Api.send_simple(chat_id, t.(:tournament_rr_enter_score))
            return
          end

          save_round_robin_match(chat_id, conv, parsed, t)
        end

        def save_round_robin_match(chat_id, conv, parsed, t)
          tournament = Tournament.find_by(id: conv["tournament_id"])
          actor = Telegram::Helpers::UserLookup.find_user(chat_id)
          return unless tournament && actor

          fields = conv["fields"] || {}
          team_a_ids = Array(fields["team_a_ids"]).map(&:to_i).uniq
          team_b_ids = Array(fields["team_b_ids"]).map(&:to_i).uniq
          doubles = tournament.format == "doubles"
          return if team_a_ids.empty? || team_b_ids.empty?
          return if doubles && (team_a_ids.size != 2 || team_b_ids.size != 2)

          pa = team_a_ids.first
          pb = team_b_ids.first
          if tournament.round_robin?
            existing = TournamentMatch.where(tournament_id: tournament.id)
                                     .where("(player_a_id = :a AND player_b_id = :b) OR (player_a_id = :b AND player_b_id = :a)", a: pa, b: pb)
                                     .exists?
            if existing
              Telegram::Api.send_simple(chat_id, t.(:processing_error))
              return
            end
          end

          result = case parsed[:result]
          when :a then "player_a"
          when :b then "player_b"
          else "draw"
          end

          court = tournament.courts.first
          unless court
            Telegram::Api.send_simple(chat_id, t.(:tournament_no_court)) rescue nil
            return
          end

          TournamentMatch.create!(
            tournament: tournament,
            player_a_id: pa,
            player_b_id: pb,
            player_a2_id: doubles ? team_a_ids.second : nil,
            player_b2_id: doubles ? team_b_ids.second : nil,
            score: parsed[:normalized],
            result: result,
            played_at: Time.current
          )
          game = Game.create!(
            tournament: tournament,
            court: court,
            user: actor,
            date: tournament.start_date || Date.current,
            sport: "tennis",
            players_count: doubles ? 4 : 2
          )

          (team_a_ids + team_b_ids).uniq.each do |uid|
            participation = Participation.find_or_initialize_by(game_id: game.id, user_id: uid)
            participation.status = "approved"
            participation.save!
          end

          mode = doubles ? "doubles" : "singles"
          Telegram::Flows::StatsScore::MatchUpserter.call(
            game: game,
            actor: actor,
            mode: mode,
            team_a_ids: team_a_ids,
            team_b_ids: team_b_ids,
            result: parsed[:result],
            played_at: Time.current,
            score: parsed[:normalized]
          )

          Telegram::Helpers::Conversation.finish(chat_id)
          Telegram::Api.send_simple(chat_id, t.(:tournament_rr_match_saved)) rescue nil
          Telegram::Handlers::TournamentsHandler.show_tournament(chat_id, tournament.id, conv["page"].to_i, message_id: conv["message_id"])
        rescue => e
          Rails.logger.error "[TournamentsFlow] save_round_robin_match error: #{e.class} #{e.message}"
          Telegram::Api.send_simple(chat_id, t.(:create_tournament_error, error: e.message)) rescue nil
        end

        def rr_cancel(chat_id, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          conv = Telegram::Helpers::Conversation.get(chat_id)
          return unless conv["flow"] == "tournament_rr_add_match"
          Telegram::Api.answer_callback(cb_id, t.(:tournament_rr_cancelled), show_alert: false) rescue nil
          tournament_id = conv["tournament_id"]
          page = conv["page"].to_i
          mid = conv["message_id"] || message_id
          Telegram::Helpers::Conversation.finish(chat_id)
          Telegram::Handlers::TournamentsHandler.show_tournament(chat_id, tournament_id, page, message_id: mid)
        end

        def show_round_robin_standings(chat_id, tournament_id, page, cb_id: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          tournament = Tournament.find_by(id: tournament_id)
          unless tournament
            Telegram::Api.answer_callback(cb_id, t.(:tournament_not_found), show_alert: false) rescue nil
            return
          end

          Telegram::Api.answer_callback(cb_id, "") rescue nil
          standings = TournamentStandings.compute(tournament)
          lines = [ t.(:tournament_rr_standings_title, id: tournament.id) ]
          lines << ""
          if standings.empty?
            lines << t.(:tournament_rr_no_matches)
          else
            standings.each_with_index do |row, idx|
              name = Telegram::Helpers::UserLookup.display_name(row[:user], fallback: "User ##{row[:user].id}")
              lines << t.(
                :tournament_rr_standings_row,
                rank: idx + 1,
                name: name,
                wins: row[:wins],
                losses: row[:losses]
              )
            end
          end

          buttons = [ [ { text: t.(:back_to_tournament), callback_data: "tournament:show:#{tournament.id}:#{page}" } ] ]
          send_or_edit_with_buttons(chat_id, lines.join("\n"), buttons, message_id: message_id)
        end

        def participant_name(participant)
          Telegram::Helpers::UserLookup.display_name(participant.user, fallback: participant.name.presence || "User ##{participant.user_id}")
        end

        def approved_participants_scope(tournament)
          return TournamentParticipant.none unless tournament
          tournament.tournament_participants.approved
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
          return unless %w[create_tournament tournament_invite tournament_edit tournament_rr_add_match].include?(conv["flow"])
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
                  [ { text: join_text, callback_data: "tournament:join_invited:#{tournament.id}:1" },
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
      end
    end
  end
end
