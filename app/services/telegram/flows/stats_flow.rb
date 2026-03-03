module Telegram
  module Flows
    class StatsFlow
      class << self
        # Публично: чтобы StatsFieldInputFlow мог вернуть пользователя в меню
        def render_menu_for(chat_id)
          render_menu(chat_id)
        end

        def handle_callback(callback_query)
          cb = Telegram::Helpers::CallbackData.parse(callback_query)
          data = cb.data
          cb_id = cb.cb_id
          chat_id = cb.chat_id
          message_id = cb.message_id
          return if chat_id.blank? || data.blank?

          case data
          when /\Atg_fill:(\d+)(?::(\d+))?\z/
            game_id = Regexp.last_match(1).to_i
            page = (Regexp.last_match(2) || "1").to_i
            start_menu(chat_id, message_id, cb_id, game_id, page: page)
            return

          when /\Atg_fill_field:(\d+):([a-z_]+)\z/
            game_id = Regexp.last_match(1).to_i
            field = Regexp.last_match(2)

            # Only basic fields are enabled; additional stats are temporarily disabled
            unless %w[hours].include?(field)
              Telegram::Api.answer_callback(cb_id, "This field is not available.", show_alert: true) rescue nil
              return
            end

            Telegram::Flows::StatsFieldInputFlow.start(
              chat_id: chat_id,
              message_id: message_id,
              cb_id: cb_id,
              game_id: game_id,
              field: field
            )
            return

          # tg_fill_more — temporarily disabled
          # when /\Atg_fill_more:(\d+)\z/
          #   game_id = Regexp.last_match(1).to_i
          #   ensure_menu_flow(chat_id, message_id, game_id)
          #   render_additional_menu(chat_id)
          #   Telegram::Api.answer_callback(cb_id) rescue nil
          #   return

          when /\Atg_fill_skip:(\d+):([a-z_]+)\z/
            game_id = Regexp.last_match(1).to_i
            field = Regexp.last_match(2)
            set_field(chat_id, cb_id, game_id, field, nil, skipped: true)
            render_menu(chat_id)
            Telegram::Api.answer_callback(cb_id) rescue nil
            return

          when /\Atg_fill_back:(\d+)\z/
            game_id = Regexp.last_match(1).to_i
            ensure_menu_flow(chat_id, message_id, game_id)
            render_menu(chat_id)
            Telegram::Api.answer_callback(cb_id) rescue nil
            return

          when /\Atg_fill_save:(\d+)\z/
            game_id = Regexp.last_match(1).to_i
            save_to_creator_stats(chat_id, cb_id, game_id)
            return

          when /\Atg_fill_cancel:(\d+)\z/
            game_id = Regexp.last_match(1).to_i
            back_to_game_card(chat_id, cb_id, game_id)
            return
          end

          nil
        rescue => e
          Rails.logger.error "[Telegram::Flows::StatsFlow] handle_callback error: #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
          Telegram::Api.answer_callback(cb_id, "Error.", show_alert: true) rescue nil
          nil
        end

        private

        def fields
          StatisticsPresenter.fields
        end

        def field_def(field)
          StatisticsPresenter.field_def(field)
        end

        def field_example(field)
          StatisticsPresenter.field_example(field)
        end

        def parse_value(field, text)
          f = field_def(field)
          return :invalid unless f

          s = text.to_s.strip
          return :invalid if s.empty?

          case StatisticsPresenter.field_type(field)
          when :float
            s = s.tr(",", ".")
            v = Float(s) rescue nil
            return :invalid if v.nil? || v.negative?
            v.round(2)
          else
            return :invalid unless s.match?(/\A\d+\z/)
            v = s.to_i
            return :invalid if v.negative?
            v
          end
        end

        def safe_conv_get(chat_id)
          Telegram::Helpers::Conversation.get(chat_id)
        rescue => e
          Rails.logger.error "[Telegram::Flows::StatsFlow] Conversation.get failed chat_id=#{chat_id}: #{e.class}: #{e.message}"
          {}
        end

        def safe_conv_set(chat_id, payload)
          Telegram::Helpers::Conversation.set(chat_id, payload)
        rescue => e
          Rails.logger.error "[Telegram::Flows::StatsFlow] Conversation.set failed chat_id=#{chat_id} payload_keys=#{payload.keys.inspect}: #{e.class}: #{e.message}"
          false
        end

        def start_menu(chat_id, message_id, cb_id, game_id, page:)
          game = Game.find_by(id: game_id)
          unless game
            Telegram::Api.answer_callback(cb_id, "Game not found.", show_alert: true) rescue nil
            return
          end

          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          unless can_fill_stats_for_game?(user, game)
            Telegram::Api.answer_callback(cb_id, "Only game participants or an admin can fill statistics.", show_alert: true) rescue nil
            return
          end

          unless game.started_for_ui?
            start_at = game.start_at_for_ui
            tz = game.creator_time_zone
            msg =
              if start_at
                "Statistics will be available after the game starts: #{start_at.strftime("%Y-%m-%d %H:%M")} (#{tz})"
              else
                "Statistics will be available after the game starts."
              end
            Telegram::Api.answer_callback(cb_id, msg, show_alert: true) rescue nil
            return
          end

          conv = safe_conv_get(chat_id)

          last_reset = game.last_participations_reset_at
          saved_entry =
            if last_reset.present?
              PlayerStatisticEntry.where(game: game, source: "telegram")
                                 .where("recorded_at >= ?", last_reset.beginning_of_day)
                                 .order(recorded_at: :desc)
                                 .first
            else
              PlayerStatisticEntry.where(game: game, source: "telegram")
                                 .order(recorded_at: :desc)
                                 .first
            end
          saved_fields = (saved_entry&.data || {}).stringify_keys

          entered =
            if conv.is_a?(Hash) && conv["game_id"].to_i == game_id && conv["fields"].is_a?(Hash)
              conv["fields"]
            else
              saved_fields
            end

          safe_conv_set(
            chat_id,
            {
              "flow" => "game_stats_menu",
              "game_id" => game_id,
              "page" => page.to_i,
              "message_id" => message_id,
              "fields" => entered
            }
          )

          render_menu(chat_id, game_id: game_id, message_id: message_id, entered: entered)
          Telegram::Api.answer_callback(cb_id) rescue nil
        end

        def render_menu(chat_id, game_id: nil, message_id: nil, entered: nil)
          conv = safe_conv_get(chat_id)
          game_id = game_id.presence || conv["game_id"]
          message_id = message_id.presence || conv["message_id"]
          entered = entered.is_a?(Hash) ? entered : (conv["fields"].is_a?(Hash) ? conv["fields"] : {})

          game_id = game_id.to_i

          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          lines = []
          lines << "*#{t.call(:statistics)}*"
          lines << "Game ##{game_id}"
          lines << ""
          lines << t.call(:stats_entered_section)

          game = game_id > 0 ? Game.find_by(id: game_id) : nil
          last_reset = game&.last_participations_reset_at

          score =
            if game_id > 0
              scope = Match.where(game_id: game_id).where.not(score: [ nil, "" ])
              scope = scope.where("played_at >= ?", last_reset.beginning_of_day) if last_reset.present?
              scope.order(updated_at: :desc).limit(1).pick(:score)
            end
          shown_score = score.to_s.strip.presence || "—"
          lines << "• #{t.call(:stats_score_line, score: shown_score)}"

          doubles_mode = game && StatisticsPresenter.hours_field_for_game(game) == :doubles_hours

          hours_key = doubles_mode ? "doubles_hours" : "singles_hours"

          hours_value = entered[hours_key] || entered[hours_key.to_sym]

          if hours_value.nil? && game
            scope = PlayerStatisticEntry.where(game: game, source: "telegram")
            scope = scope.where("recorded_at >= ?", last_reset.beginning_of_day) if last_reset.present?

            saved_entry = scope.order(recorded_at: :desc).detect do |entry|
              data = entry.data.to_h
              data.key?(hours_key) || data.key?(hours_key.to_sym)
            end
            hours_value = saved_entry&.data&.to_h&.dig(hours_key) || saved_entry&.data&.to_h&.dig(hours_key.to_sym)
          end

          display_hours =
            if hours_value.present?
              v = hours_value.to_f
              v % 1 == 0 ? v.to_i : v
            end

          lines << "• #{t.call(:game_time_label)}: #{display_hours ? "#{display_hours} #{t.call(:hours_short)}" : "—"}"

          text = lines.join("\n")

          field_buttons = [
            [ { text: t.call(:stats_enter_score_btn), callback_data: "tg_score:#{game_id}" } ],
            [ { text: t.call(:stats_enter_hours_btn), callback_data: "tg_fill_field:#{game_id}:hours" } ]
            # [ { text: "Additional match statistics", callback_data: "tg_fill_more:#{game_id}" } ]
          ]

          footer = [
            [ { text: t.call(:back_to_game), callback_data: "tg_fill_cancel:#{game_id}" } ]
          ]

          if message_id.present?
            begin
              Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, field_buttons + footer)
            rescue => e
              Rails.logger.error "[StatsFlow#render_menu] edit_message failed: #{e.class}: #{e.message}"
              Telegram::Api.send_with_buttons(chat_id, text, field_buttons + footer) rescue nil
            end
          else
            Telegram::Api.send_with_buttons(chat_id, text, field_buttons + footer) rescue nil
          end
        end

        def render_additional_menu(chat_id, game_id: nil, message_id: nil)
          conv = safe_conv_get(chat_id)
          game_id = game_id.presence || conv["game_id"]
          message_id = message_id.presence || conv["message_id"]

          game_id = game_id.to_i

          lines = []
          lines << "*Additional match statistics*"
          lines << "Game ##{game_id}"

          text = lines.join("\n")

          stat_buttons = [
            [ { text: "Aces", callback_data: "tg_fill_field:#{game_id}:aces" }, { text: "Double faults", callback_data: "tg_fill_field:#{game_id}:double_faults" } ],
            [ { text: "Break points saved", callback_data: "tg_fill_field:#{game_id}:break_points_saved" }, { text: "Break points converted", callback_data: "tg_fill_field:#{game_id}:break_points_converted" } ],
            [ { text: "Winners", callback_data: "tg_fill_field:#{game_id}:winners" }, { text: "Unforced errors", callback_data: "tg_fill_field:#{game_id}:unforced_errors" } ],
            [ { text: "Net points won", callback_data: "tg_fill_field:#{game_id}:net_points_won" }, { text: "Service points won", callback_data: "tg_fill_field:#{game_id}:service_points_won" } ],
            [ { text: "Return points won", callback_data: "tg_fill_field:#{game_id}:return_points_won" }, { text: "Games won on return", callback_data: "tg_fill_field:#{game_id}:return_games_won" } ],
            [ { text: "Total games won", callback_data: "tg_fill_field:#{game_id}:games_won_total" } ]
          ]

          footer = [
            [ { text: "Back to Statistics", callback_data: "tg_fill_back:#{game_id}" } ]
          ]

          if message_id.present?
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, stat_buttons + footer) rescue nil
          else
            Telegram::Api.send_with_buttons(chat_id, text, stat_buttons + footer) rescue nil
          end
        end

        def save_to_creator_stats(chat_id, cb_id, game_id)
          game = Game.find_by(id: game_id)
          unless game
            Telegram::Api.answer_callback(cb_id, "Game not found.", show_alert: true) rescue nil
            return
          end

          actor = Telegram::Helpers::UserLookup.find_user(chat_id)
          unless can_fill_stats_for_game?(actor, game)
            Telegram::Api.answer_callback(cb_id, "Only game participants or an admin can fill statistics.", show_alert: true) rescue nil
            return
          end

          unless game.started_for_ui?
            Telegram::Api.answer_callback(cb_id, "Statistics is locked until the game starts.", show_alert: true) rescue nil
            return
          end

          conv = Telegram::Helpers::Conversation.get(chat_id) rescue {}
          entered = (conv.is_a?(Hash) && conv["fields"].is_a?(Hash)) ? conv["fields"] : {}

          data = {}
          fields.each do |f|
            key = f[:key].to_s
            next unless entered.key?(key)
            val = entered[key]
            next if val.nil?
            data[key] = val
          end

          recorded_at = Time.current

          PlayerStatistics::ApplyEntryToParticipantsService.new(
            game: game,
            actor: actor,
            data: data,
            source: "telegram",
            recorded_at: recorded_at
          ).call

          Telegram::Api.answer_callback(cb_id, "Saved.", show_alert: false) rescue nil
          back_to_game_card(chat_id, nil, game_id, keep_conv: false)
        rescue ActiveRecord::RecordNotUnique
          Telegram::Api.answer_callback(cb_id, "Already saved for this game.", show_alert: true) rescue nil
        rescue => e
          Rails.logger.error "[Telegram::Flows::StatsFlow] save_to_creator_stats error: #{e.class}: #{e.message}"
          Telegram::Api.answer_callback(cb_id, "Save failed.", show_alert: true) rescue nil
        end

        def back_to_game_card(chat_id, cb_id, game_id, keep_conv: true)
          conv = Telegram::Helpers::Conversation.get(chat_id) rescue {}
          page = (conv.is_a?(Hash) && conv["page"].to_i > 0) ? conv["page"].to_i : 1
          message_id = conv.is_a?(Hash) ? conv["message_id"] : nil

          Telegram::Helpers::Conversation.finish(chat_id) rescue nil unless keep_conv

          Telegram::Handlers::GamesHandler.show_game(chat_id, game_id, page, message_id: message_id) rescue nil
          Telegram::Api.answer_callback(cb_id) rescue nil if cb_id
        end

        def ensure_menu_flow(chat_id, message_id, game_id)
          conv = Telegram::Helpers::Conversation.get(chat_id) rescue {}
          entered_fields = (conv.is_a?(Hash) && conv["fields"].is_a?(Hash)) ? conv["fields"] : {}
          page = (conv.is_a?(Hash) && conv["page"].to_i > 0) ? conv["page"].to_i : 1

          safe_conv_set(
            chat_id,
            {
              "flow" => "game_stats_menu",
              "game_id" => game_id,
              "page" => page,
              "message_id" => message_id || (conv.is_a?(Hash) ? conv["message_id"] : nil),
              "fields" => entered_fields
            }
          )
        end

        def set_field(chat_id, _cb_id, game_id, field, value, skipped:)
          conv = Telegram::Helpers::Conversation.get(chat_id) rescue {}
          entered = (conv.is_a?(Hash) && conv["fields"].is_a?(Hash)) ? conv["fields"] : {}
          return unless field_def(field)

          key = field.to_s
          entered[key] = skipped ? nil : value

          safe_conv_set(
            chat_id,
            (conv.is_a?(Hash) ? conv.merge("fields" => entered, "game_id" => game_id) : { "fields" => entered, "game_id" => game_id })
          )
        end

        def can_fill_stats_for_game?(user, game)
          return false unless user && game
          return true if user.admin? || user.id == game.user_id

          participations = game.participations
          if participations.respond_to?(:approved)
            participations.approved.exists?(user_id: user.id)
          else
            participations.exists?(user_id: user.id, status: "approved")
          end
        end
      end
    end
  end
end
