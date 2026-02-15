module Telegram
  module Flows
    module Games
      module Manage
        module CreateFlow
          # Step-by-step game creation conversation
          #
          # Required steps: date, time, players_count, court
          # Optional steps: recurring, prebooking (only if recurring), with_coach, sport, skill_level
          #
          # Conversation state stored in Rails.cache via Telegram::Helpers::Conversation
          # with flow: "create_game"

          REQUIRED_STEPS = %w[date time players_count court].freeze
          OPTIONAL_STEPS = %w[recurring prebooking with_coach sport skill_level].freeze
          ALL_STEPS = (REQUIRED_STEPS + OPTIONAL_STEPS).freeze
          TOTAL_STEPS = ALL_STEPS.size

          class << self
            def handle_callback(callback)
              cb = Telegram::Helpers::CallbackData.parse(callback)
              locale = Telegram::Helpers::UserLookup.locale_for(cb.chat_id)
              t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
              sync_wizard_message_id(cb.chat_id, cb.message_id)

              case cb.data
              when /\Agame:create\z/
                start_create_game(cb.chat_id, cb_id: cb.cb_id, message_id: cb.message_id)
                nil

              when /\Agame:create:cancel\z/
                Telegram::Api.answer_callback(cb.cb_id, t.(:create_game_cancelled)) rescue nil
                Telegram::Helpers::Conversation.finish(cb.chat_id)
                Telegram::Handlers::MenuHandler.menu(cb.chat_id, message_id: cb.message_id)
                nil

              when /\Agame:create:skip\z/
                Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
                handle_skip(cb.chat_id, cb.message_id)
                nil

              when /\Agame:create:court:(\d+)\z/
                court_id = $1.to_i
                Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
                process_court_selection(cb.chat_id, court_id)
                nil

              when /\Agame:create:court_new\z/
                Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
                # Save game creation fields before switching to court creation
                conv = Telegram::Helpers::Conversation.get(cb.chat_id)
                game_fields = conv["fields"] || {}
                # Store game fields in a separate cache key so they survive the court creation
                Rails.cache.write("tg:game_create_fields:#{cb.chat_id}", game_fields, expires_in: 2.hours)
                Telegram::Flows::CourtCreateFlow.start(cb.chat_id, return_to: "game_create", message_id: cb.message_id)
                nil

              when /\Agame:create:court_page:(\d+)\z/
                page = $1.to_i
                Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
                send_court_selection(cb.chat_id, page, message_id: cb.message_id)
                nil

              when /\Agame:create:recurring:(yes|no)\z/
                val = $1 == "yes"
                Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
                process_boolean_step(cb.chat_id, "recurring", val)
                nil

              when /\Agame:create:prebooking:(yes|no)\z/
                val = $1 == "yes"
                Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
                process_boolean_step(cb.chat_id, "prebooking", val)
                nil

              when /\Agame:create:with_coach:(yes|no)\z/
                val = $1 == "yes"
                Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
                process_boolean_step(cb.chat_id, "with_coach", val)
                nil

              when /\Agame:create:players:(\d+)\z/
                count = $1.to_i
                Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
                conv = Telegram::Helpers::Conversation.get(cb.chat_id)
                unless [2, 4].include?(count)
                  re_prompt_with_error(cb.chat_id, conv, "players_count", t.(:create_game_players_invalid))
                  return nil
                end
                conv["fields"] ||= {}
                conv["fields"]["players_count"] = count
                save_and_advance(cb.chat_id, conv, "players_count")
                nil

              when /\Agame:create:sport:(.+)\z/
                sport = $1
                Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
                process_sport_selection(cb.chat_id, sport)
                nil

              when /\Agame:create:skill:(.+)\z/
                level = $1
                Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
                process_skill_selection(cb.chat_id, level)
                nil

              # Legacy callbacks for old-style create flow (confirm/cancel with game id)
              when /\Agame:create:confirm:(\d+)\z/
                gid = $1.to_i
                Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
                Telegram::Handlers::GamesHandler.show_game(cb.chat_id, gid, 1, message_id: cb.message_id) rescue nil
                nil

              when /\Agame:create:cancel:(\d+)(?::(\d+))?\z/
                gid = $1.to_i
                orig_msg_id = $2 ? $2.to_i : nil
                Telegram::Api.answer_callback(cb.cb_id, t.(:create_game_cancelled)) rescue nil
                begin
                  game = Game.find_by(id: gid)
                  if game
                    court_id = game.court_id
                    game.destroy rescue nil
                    if orig_msg_id && court_id
                      Telegram::Handlers::CourtsHandler.show_court(cb.chat_id, court_id, 1, message_id: orig_msg_id) rescue nil
                    end
                  end
                rescue => e
                  Rails.logger.error "[CreateFlow] cancel error: #{e.class} #{e.message}"
                end
                nil

              when /\Agame:create:field:(\w+):(\d+)\z/
                Telegram::Flows::Games::EditPrompter.handle_callback(callback) rescue nil
                Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
                nil

              else
                nil
              end
            rescue => e
              Rails.logger.error "[CreateFlow] #{e.class} #{e.message}"
              nil
            end

            def start_create_game(chat_id, cb_id: nil, message_id: nil)
              locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
              t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

              user = Telegram::Helpers::UserLookup.find_user(chat_id)
              unless user
                Telegram::Api.answer_callback(cb_id, t.(:no_linked_account)) rescue nil
                return
              end

              Telegram::Api.answer_callback(cb_id, t.(:create_game_reply)) rescue nil

              # Initialize conversation state
              Telegram::Helpers::Conversation.start(chat_id, {
                "flow" => "create_game",
                "step" => "date",
                "fields" => {},
                "wizard_message_id" => message_id
              })

              send_step_prompt(chat_id, "date", message_id: message_id)
            rescue => e
              Rails.logger.error "[CreateFlow] start_create_game error: #{e.class} #{e.message}"
              nil
            end

            # Called by ReplyProcessor when flow == "create_game"
            def process_text(message)
              chat_id = (message.dig("chat", "id") || message.dig("from", "id")).to_s
              text = message["text"].to_s.strip
              conv = Telegram::Helpers::Conversation.get(chat_id)
              return false unless conv["flow"] == "create_game"

              step = conv["step"]
              locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
              t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
              consume_user_text_message(chat_id, message)

              case step
              when "date"
                date = begin; Date.parse(text); rescue; nil; end
                unless date
                  re_prompt_with_error(chat_id, conv, step, t.(:create_game_date_invalid))
                  return true
                end
                if date < Date.current
                  re_prompt_with_error(chat_id, conv, step, t.(:create_game_date_past))
                  return true
                end
                conv["fields"]["date"] = date.to_s
                save_and_advance(chat_id, conv, "date")

              when "time"
                unless text.match?(/\A\d{1,2}:\d{2}\z/)
                  re_prompt_with_error(chat_id, conv, step, t.(:create_game_time_invalid))
                  return true
                end
                h, m = text.split(":").map(&:to_i)
                unless h.between?(0, 23) && m.between?(0, 59)
                  re_prompt_with_error(chat_id, conv, step, t.(:create_game_time_invalid))
                  return true
                end
                conv["fields"]["time"] = text
                save_and_advance(chat_id, conv, "time")

              when "players_count"
                count = text.to_i
                unless [2, 4].include?(count)
                  re_prompt_with_error(chat_id, conv, step, t.(:create_game_players_invalid))
                  return true
                end
                conv["fields"]["players_count"] = count
                save_and_advance(chat_id, conv, "players_count")

              else
                # Unexpected text input for this step — remind user to use buttons
                re_prompt_with_error(chat_id, conv, step, t.(:please_use_buttons))
              end

              true
            rescue => e
              Rails.logger.error "[CreateFlow] process_text error: #{e.class} #{e.message}"
              true
            end

            private

            def step_number(step)
              ALL_STEPS.index(step).to_i + 1
            end

            def send_step_prompt(chat_id, step, message_id: nil, error_text: nil)
              locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
              t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
              message_id ||= Telegram::Helpers::Conversation.get(chat_id)["wizard_message_id"]
              entered_text = entered_fields_text(chat_id, locale: locale)

              header = t.(:create_game_step, step: step_number(step), total: TOTAL_STEPS)
              cancel_row = [{ text: t.(:cancel_btn), callback_data: "game:create:cancel" }]

              case step
              when "date"
                text = build_step_text(header, t.(:create_game_date), error_text, entered_text: entered_text)
                buttons = [cancel_row]
                send_or_edit_step_prompt(chat_id, text, buttons, message_id: message_id)

              when "time"
                text = build_step_text(header, t.(:create_game_time), error_text, entered_text: entered_text)
                buttons = [cancel_row]
                send_or_edit_step_prompt(chat_id, text, buttons, message_id: message_id)

              when "players_count"
                text = build_step_text(header, t.(:create_game_players), error_text, entered_text: entered_text)
                # Quick-pick buttons for common counts
                row1 = [2, 4].map { |n| { text: n.to_s, callback_data: "game:create:players:#{n}" } }
                buttons = [row1, cancel_row]
                send_or_edit_step_prompt(chat_id, text, buttons, message_id: message_id)

              when "court"
                send_court_selection(chat_id, 1, message_id: message_id, error_text: error_text)

              when "recurring"
                text = build_step_text(header, t.(:create_game_recurring), error_text, entered_text: entered_text)
                buttons = [
                  [
                    { text: t.(:yes_label), callback_data: "game:create:recurring:yes" },
                    { text: t.(:no_label),  callback_data: "game:create:recurring:no" }
                  ],
                  [{ text: t.(:skip_btn), callback_data: "game:create:skip" }],
                  cancel_row
                ]
                send_or_edit_step_prompt(chat_id, text, buttons, message_id: message_id)

              when "prebooking"
                # Only show if recurring was set to true
                conv = Telegram::Helpers::Conversation.get(chat_id)
                unless conv.dig("fields", "recurring")
                  save_and_advance(chat_id, conv, "prebooking")
                  return
                end
                text = build_step_text(header, t.(:create_game_prebooking), error_text, entered_text: entered_text)
                buttons = [
                  [
                    { text: t.(:yes_label), callback_data: "game:create:prebooking:yes" },
                    { text: t.(:no_label),  callback_data: "game:create:prebooking:no" }
                  ],
                  [{ text: t.(:skip_btn), callback_data: "game:create:skip" }],
                  cancel_row
                ]
                send_or_edit_step_prompt(chat_id, text, buttons, message_id: message_id)

              when "with_coach"
                text = build_step_text(header, t.(:create_game_with_coach), error_text, entered_text: entered_text)
                buttons = [
                  [
                    { text: t.(:yes_label), callback_data: "game:create:with_coach:yes" },
                    { text: t.(:no_label),  callback_data: "game:create:with_coach:no" }
                  ],
                  [{ text: t.(:skip_btn), callback_data: "game:create:skip" }],
                  cancel_row
                ]
                send_or_edit_step_prompt(chat_id, text, buttons, message_id: message_id)

              when "sport"
                text = build_step_text(header, t.(:create_game_sport), error_text, entered_text: entered_text)
                sport_buttons = User::SPORTS.map { |s| [{ text: s, callback_data: "game:create:sport:#{s}" }] }
                buttons = sport_buttons + [
                  [{ text: t.(:skip_btn), callback_data: "game:create:skip" }],
                  cancel_row
                ]
                send_or_edit_step_prompt(chat_id, text, buttons, message_id: message_id)

              when "skill_level"
                text = build_step_text(header, t.(:create_game_skill), error_text, entered_text: entered_text)
                level_buttons = User::SKILL_LEVELS.map { |l| [{ text: l.titleize, callback_data: "game:create:skill:#{l}" }] }
                buttons = level_buttons + [
                  [{ text: t.(:create_game_any_level), callback_data: "game:create:skill:any" }],
                  [{ text: t.(:skip_btn), callback_data: "game:create:skip" }],
                  cancel_row
                ]
                send_or_edit_step_prompt(chat_id, text, buttons, message_id: message_id)
              end
            end

            def send_court_selection(chat_id, page, message_id: nil, error_text: nil)
              locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
              t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
              user = Telegram::Helpers::UserLookup.find_user(chat_id)
              entered_text = entered_fields_text(chat_id, locale: locale)

              courts = Court.visible_to(user).order(:name).to_a
              per_page = 5
              total_pages = [(courts.size.to_f / per_page).ceil, 1].max
              page = [[page, 1].max, total_pages].min
              offset = (page - 1) * per_page
              slice = courts.slice(offset, per_page) || []

              step_num = step_number("court")
              header = t.(:create_game_step, step: step_num, total: TOTAL_STEPS)
              text = build_step_text(header, t.(:create_game_court), error_text, entered_text: entered_text)
              cancel_row = [{ text: t.(:cancel_btn), callback_data: "game:create:cancel" }]

              if courts.empty?
                text = build_step_text(header, t.(:create_game_no_courts), error_text, entered_text: entered_text)
                buttons = [
                  [{ text: t.(:create_game_court_new), callback_data: "game:create:court_new" }],
                  cancel_row
                ]
              else
                buttons = slice.map { |c| [{ text: c.name, callback_data: "game:create:court:#{c.id}" }] }
                nav = []
                nav << { text: t.(:prev_page), callback_data: "game:create:court_page:#{page - 1}" } if page > 1
                nav << { text: t.(:next_page), callback_data: "game:create:court_page:#{page + 1}" } if page < total_pages
                buttons << nav unless nav.empty?
                buttons << [{ text: t.(:create_game_court_new), callback_data: "game:create:court_new" }]
                buttons << cancel_row
              end

              if message_id
                Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons)
              else
                Telegram::Api.send_with_buttons(chat_id, text, buttons)
              end
            end

            def process_court_selection(chat_id, court_id)
              conv = Telegram::Helpers::Conversation.get(chat_id)
              conv["fields"]["court_id"] = court_id
              save_and_advance(chat_id, conv, "court")
            end

            def process_boolean_step(chat_id, step, value)
              conv = Telegram::Helpers::Conversation.get(chat_id)
              conv["fields"][step] = value
              save_and_advance(chat_id, conv, step)
            end

            def process_sport_selection(chat_id, sport)
              conv = Telegram::Helpers::Conversation.get(chat_id)
              conv["fields"]["sport"] = sport
              save_and_advance(chat_id, conv, "sport")
            end

            def process_skill_selection(chat_id, level)
              conv = Telegram::Helpers::Conversation.get(chat_id)
              level = nil if level == "any"
              conv["fields"]["skill_level"] = level
              save_and_advance(chat_id, conv, "skill_level")
            end

            def handle_skip(chat_id, message_id)
              conv = Telegram::Helpers::Conversation.get(chat_id)
              conv["wizard_message_id"] ||= message_id
              step = conv["step"]
              # Can only skip optional steps
              if OPTIONAL_STEPS.include?(step)
                save_and_advance(chat_id, conv, step)
              end
            end

            def save_and_advance(chat_id, conv, current_step)
              next_step = next_step_after(current_step, conv)

              if next_step
                conv["step"] = next_step
                Telegram::Helpers::Conversation.set(chat_id, conv)
                send_step_prompt(chat_id, next_step, message_id: conv["wizard_message_id"])
              else
                # All steps done — create the game
                finalize_game(chat_id, conv)
              end
            end

            def send_or_edit_step_prompt(chat_id, text, buttons, message_id: nil)
              if message_id
                Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons)
              else
                Telegram::Api.send_with_buttons(chat_id, text, buttons)
              end
            end

            def re_prompt_with_error(chat_id, conv, step, error_text)
              send_step_prompt(chat_id, step, message_id: conv["wizard_message_id"], error_text: error_text)
            end

            def build_step_text(header, prompt_text, error_text = nil, entered_text: nil)
              parts = [header]
              parts << entered_text unless entered_text.to_s.empty?
              parts << prompt_text
              base = parts.join("\n\n")
              return base if error_text.to_s.empty?
              "#{error_text}\n\n#{base}"
            end

            def entered_fields_text(chat_id, locale:)
              conv = Telegram::Helpers::Conversation.get(chat_id)
              fields = conv["fields"] || {}
              return nil if fields.empty?

              ru = locale.to_s.start_with?("ru")
              yes = ru ? "Да" : "Yes"
              no = ru ? "Нет" : "No"
              labels = if ru
                {
                  date: "Дата",
                  time: "Время",
                  players_count: "Игроки",
                  court: "Корт",
                  recurring: "Повторение",
                  prebooking: "Предбронирование",
                  with_coach: "Тренер",
                  sport: "Спорт",
                  skill_level: "Уровень"
                }
              else
                {
                  date: "Date",
                  time: "Time",
                  players_count: "Players",
                  court: "Court",
                  recurring: "Recurring",
                  prebooking: "Prebooking",
                  with_coach: "Coach",
                  sport: "Sport",
                  skill_level: "Level"
                }
              end

              lines = []
              lines << "#{labels[:date]}: #{fields["date"]}" if fields["date"].present?
              lines << "#{labels[:time]}: #{fields["time"]}" if fields["time"].present?
              lines << "#{labels[:players_count]}: #{fields["players_count"]}" if fields["players_count"].present?

              if fields["court_id"].present?
                court_name = Court.find_by(id: fields["court_id"])&.name || "##{fields["court_id"]}"
                lines << "#{labels[:court]}: #{court_name}"
              end

              if fields.key?("recurring")
                lines << "#{labels[:recurring]}: #{fields["recurring"] ? yes : no}"
              end

              if fields.key?("prebooking")
                lines << "#{labels[:prebooking]}: #{fields["prebooking"] ? yes : no}"
              end

              if fields.key?("with_coach")
                lines << "#{labels[:with_coach]}: #{fields["with_coach"] ? yes : no}"
              end

              lines << "#{labels[:sport]}: #{fields["sport"]}" if fields["sport"].present?

              if fields.key?("skill_level")
                skill = fields["skill_level"].presence || (ru ? "Любой" : "Any")
                lines << "#{labels[:skill_level]}: #{skill}"
              end

              lines.any? ? lines.join("\n") : nil
            end

            def consume_user_text_message(chat_id, message)
              message_id = message["message_id"]
              return unless message_id
              Telegram::Api.post("deleteMessage", { "chat_id" => chat_id.to_s, "message_id" => message_id.to_i })
            rescue => e
              Rails.logger.debug "[CreateFlow] consume_user_text_message error: #{e.class} #{e.message}"
            end

            def sync_wizard_message_id(chat_id, message_id)
              return unless message_id
              conv = Telegram::Helpers::Conversation.get(chat_id)
              return unless conv["flow"] == "create_game"
              return if conv["wizard_message_id"] == message_id
              conv["wizard_message_id"] = message_id
              Telegram::Helpers::Conversation.set(chat_id, conv)
            end

            def next_step_after(current, conv)
              idx = ALL_STEPS.index(current)
              return nil unless idx

              candidate = ALL_STEPS[idx + 1]
              return nil unless candidate

              # Skip prebooking if recurring is not enabled
              if candidate == "prebooking" && !conv.dig("fields", "recurring")
                return next_step_after("prebooking", conv)
              end

              candidate
            end

            def finalize_game(chat_id, conv)
              locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
              t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

              user = Telegram::Helpers::UserLookup.find_user(chat_id)
              fields = conv["fields"] || {}
              wizard_message_id = conv["wizard_message_id"]

              Telegram::Helpers::Conversation.finish(chat_id)

              game = Game.new(
                user_id: user.id,
                court_id: fields["court_id"],
                date: fields["date"],
                time: fields["time"],
                players_count: fields["players_count"] || 4,
                recurring: fields["recurring"] || false,
                prebooking_enabled: (fields["recurring"] && fields["prebooking"]) || false,
                with_coach: fields["with_coach"] || false,
                sport: fields["sport"],
                skill_level: fields["skill_level"]
              )

              if game.save
                Telegram::Handlers::GamesHandler.show_game(chat_id, game.id, 1, message_id: wizard_message_id) rescue nil
              else
                Telegram::Api.send_simple(chat_id, t.(:create_game_error, error: game.errors.full_messages.join(", ")))
                Telegram::Handlers::MenuHandler.menu(chat_id, message_id: wizard_message_id)
              end
            rescue => e
              Rails.logger.error "[CreateFlow] finalize_game error: #{e.class} #{e.message}"
              Telegram::Api.send_simple(chat_id, t.(:create_game_error, error: e.message)) rescue nil
            end
          end
        end
      end
    end
  end
end
