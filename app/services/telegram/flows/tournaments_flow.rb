module Telegram
  module Flows
    class TournamentsFlow
      # Step-by-step tournament creation + join/leave/show callbacks
      #
      # Steps: name, players_count, games_count, format, court, start_date
      # Conversation state stored via Telegram::Helpers::Conversation with flow: "create_tournament"

      STEPS = %w[name players_count games_count format court start_date].freeze
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
            conv["message_id"] = cb.message_id if cb.message_id
            Telegram::Helpers::Conversation.set(cb.chat_id, conv)
            send_step_prompt(cb.chat_id, "name", message_id: conv["message_id"])

          when /\Atournament:create:cancel\z/
            Telegram::Api.answer_callback(cb.cb_id, t.(:create_tournament_cancelled)) rescue nil
            Telegram::Helpers::Conversation.finish(cb.chat_id)
            Telegram::Handlers::MenuHandler.menu(cb.chat_id, message_id: cb.message_id)

          when /\Atournament:create:skip\z/
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            handle_skip(cb.chat_id, cb.message_id)

          when /\Atournament:create:players:(\d+)\z/
            count = $1.to_i
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            conv = Telegram::Helpers::Conversation.get(cb.chat_id)
            conv["fields"] ||= {}
            conv["fields"]["players_count"] = count
            save_and_advance(cb.chat_id, conv, "players_count", message_id: cb.message_id)

          when /\Atournament:create:games_count:(\d+)\z/
            count = $1.to_i
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            conv = Telegram::Helpers::Conversation.get(cb.chat_id)
            conv["fields"] ||= {}
            conv["fields"]["games_count"] = count
            save_and_advance(cb.chat_id, conv, "games_count", message_id: cb.message_id)

          when /\Atournament:create:format:(singles|doubles)\z/
            fmt = $1
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            conv = Telegram::Helpers::Conversation.get(cb.chat_id)
            conv["fields"] ||= {}
            conv["fields"]["format"] = fmt
            save_and_advance(cb.chat_id, conv, "format", message_id: cb.message_id)

          when /\Atournament:create:court:(\d+)\z/
            court_id = $1.to_i
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            conv = Telegram::Helpers::Conversation.get(cb.chat_id)
            conv["fields"] ||= {}
            conv["fields"]["court_id"] = court_id
            save_and_advance(cb.chat_id, conv, "court", message_id: cb.message_id)

          when /\Atournament:create:court_page:(\d+)\z/
            page = $1.to_i
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            send_court_selection(cb.chat_id, page, message_id: cb.message_id)

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
          return false unless conv["flow"] == "create_tournament"

          delete_input_message(message)

          step = conv["step"]
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

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
            [{ text: locale == "ru" ? "Создать в боте" : "Create in bot", callback_data: "tournament:create:bot" }],
            [{ text: locale == "ru" ? "Создать на сайте" : "Create on website", url: "https://getcourt.co/tournaments/new" }],
            [{ text: t.(:cancel_btn), callback_data: "tournament:create:cancel" }]
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
          cancel_row = [{ text: t.(:cancel_btn), callback_data: "tournament:create:cancel" }]

          case step
          when "name"
            text = build_step_text(chat_id, header, t.(:create_tournament_name))
            buttons = [cancel_row]
            send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)

          when "players_count"
            text = build_step_text(chat_id, header, t.(:create_tournament_players))
            row = [2, 4, 8, 16].map { |n| { text: n.to_s, callback_data: "tournament:create:players:#{n}" } }
            buttons = [row, cancel_row]
            send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)

          when "games_count"
            text = build_step_text(chat_id, header, t.(:create_tournament_games_count))
            row = [3, 5, 7].map { |n| { text: n.to_s, callback_data: "tournament:create:games_count:#{n}" } }
            buttons = [row, [{ text: t.(:skip_btn), callback_data: "tournament:create:skip" }], cancel_row]
            send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)

          when "format"
            text = build_step_text(chat_id, header, t.(:create_tournament_format))
            buttons = [
              [
                { text: "Singles", callback_data: "tournament:create:format:singles" },
                { text: "Doubles", callback_data: "tournament:create:format:doubles" }
              ],
              [{ text: t.(:skip_btn), callback_data: "tournament:create:skip" }],
              cancel_row
            ]
            send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)

          when "court"
            send_court_selection(chat_id, 1, message_id: message_id)

          when "start_date"
            text = build_step_text(chat_id, header, t.(:create_tournament_date))
            buttons = [[{ text: t.(:skip_btn), callback_data: "tournament:create:skip" }], cancel_row]
            send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
          end
        end

        def send_court_selection(chat_id, page, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          user = Telegram::Helpers::UserLookup.find_user(chat_id)

          courts = Court.visible_to(user).order(:name).to_a
          per_page = 5
          total_pages = [(courts.size.to_f / per_page).ceil, 1].max
          page = [[page, 1].max, total_pages].min
          offset = (page - 1) * per_page
          slice = courts.slice(offset, per_page) || []

          step_num = step_number("court")
          header = t.(:create_tournament_step, step: step_num, total: TOTAL_STEPS)
          text = build_step_text(chat_id, header, t.(:create_tournament_court))
          cancel_row = [{ text: t.(:cancel_btn), callback_data: "tournament:create:cancel" }]

          buttons = slice.map { |c| [{ text: c.name, callback_data: "tournament:create:court:#{c.id}" }] }

          nav = []
          nav << { text: t.(:prev_page), callback_data: "tournament:create:court_page:#{page - 1}" } if page > 1
          nav << { text: t.(:next_page), callback_data: "tournament:create:court_page:#{page + 1}" } if page < total_pages
          buttons << nav unless nav.empty?
          buttons << [{ text: t.(:skip_btn), callback_data: "tournament:create:skip" }]
          buttons << cancel_row

          send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
        end

        def handle_skip(chat_id, message_id = nil)
          conv = Telegram::Helpers::Conversation.get(chat_id)
          step = conv["step"]
          # Can skip: games_count, format, court, start_date (not name or players_count)
          skippable = %w[games_count format court start_date]
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

          Telegram::Helpers::Conversation.finish(chat_id)

          tournament = Tournament.new(
            user_id: user.id,
            name: fields["name"],
            players_count: fields["players_count"] || 4,
            games_count: fields["games_count"],
            format: fields["format"],
            start_date: fields["start_date"]
          )

          # Link court if provided
          if fields["court_id"].present?
            tournament.court_ids = [fields["court_id"]]
          end

          if tournament.save
            Telegram::Api.send_simple(chat_id, t.(:create_tournament_success))
            Telegram::Handlers::TournamentsHandler.show_tournament(chat_id, tournament.id, 1) rescue nil
          else
            Telegram::Api.send_simple(chat_id, t.(:create_tournament_error, error: tournament.errors.full_messages.join(", ")))
            Telegram::Handlers::MenuHandler.menu(chat_id)
          end
        rescue => e
          Rails.logger.error "[TournamentsFlow] finalize_tournament error: #{e.class} #{e.message}"
          t = ->(key, **args) { Telegram::I18n.t(key, locale: "ru", **args) }
          Telegram::Api.send_simple(chat_id, t.(:create_tournament_error, error: e.message)) rescue nil
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

          if tournament.tournament_participants.exists?(user_id: user.id)
            Telegram::Api.answer_callback(cb_id, t.(:tournament_already_joined), show_alert: false) rescue nil
          else
            tournament.tournament_participants.create!(user: user, name: user.name.presence || user.email)
            Telegram::Api.answer_callback(cb_id, t.(:tournament_joined), show_alert: false) rescue nil
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
              "format" => "Формат", "court_id" => "Корт", "start_date" => "Дата начала" }
          else
            { "name" => "Name", "players_count" => "Players", "games_count" => "Games",
              "format" => "Format", "court_id" => "Court", "start_date" => "Start date" }
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
          return nil if lines.empty?

          title = locale == "ru" ? "Введено:" : "Entered:"
          ([title] + lines).join("\n")
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
          return unless conv["flow"] == "create_tournament"
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
      end
    end
  end
end
