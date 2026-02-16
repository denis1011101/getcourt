module Telegram
  module Flows
    module CourtCreateFlow
      # Step-by-step court creation conversation
      #
      # Required steps: name, location
      # Optional steps: contact_type, contact_value
      #
      # Conversation state stored via Telegram::Helpers::Conversation
      # with flow: "create_court"

      REQUIRED_STEPS = %w[name location].freeze
      OPTIONAL_STEPS = %w[contact_type contact_value].freeze
      ALL_STEPS = (REQUIRED_STEPS + OPTIONAL_STEPS).freeze
      TOTAL_STEPS = ALL_STEPS.size

      class << self
        def start(chat_id, return_to: nil, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          unless user
            Telegram::Api.send_simple(chat_id, t.(:no_linked_account))
            return
          end

          Telegram::Helpers::Conversation.start(chat_id, {
            "flow" => "create_court",
            "step" => "entry",
            "fields" => {},
            "return_to" => return_to,
            "message_id" => message_id
          })

          send_start_options(chat_id, message_id: message_id)
        rescue => e
          Rails.logger.error "[CourtCreateFlow] start error: #{e.class} #{e.message}"
        end

        def handle_callback(callback)
          cb = Telegram::Helpers::CallbackData.parse(callback)
          locale = Telegram::Helpers::UserLookup.locale_for(cb.chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          case cb.data
          when /\Acourt:create\z/
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            start(cb.chat_id, message_id: cb.message_id)
            nil

          when /\Acourt:create:bot\z/
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            conv = Telegram::Helpers::Conversation.get(cb.chat_id)
            return nil unless conv["flow"] == "create_court"
            conv["step"] = "name"
            conv["message_id"] = cb.message_id if cb.message_id
            Telegram::Helpers::Conversation.set(cb.chat_id, conv)
            send_step_prompt(cb.chat_id, "name", message_id: conv["message_id"])
            nil

          when /\Acourt:create:cancel\z/
            Telegram::Api.answer_callback(cb.cb_id, t.(:create_court_cancelled)) rescue nil
            conv = Telegram::Helpers::Conversation.get(cb.chat_id)
            return_to = conv["return_to"]
            resume_message_id = conv["message_id"] || cb.message_id
            Telegram::Helpers::Conversation.finish(cb.chat_id)

            # Remove reply keyboard if it was shown
            Telegram::Api.send_api("sendMessage", {
              chat_id: cb.chat_id,
              text: ".",
              reply_markup: { remove_keyboard: true }
            }) rescue nil

            if return_to == "game_create"
              # Restore saved game fields and return to court selection step
              saved_fields = Rails.cache.read("tg:game_create_fields:#{cb.chat_id}") || {}
              Rails.cache.delete("tg:game_create_fields:#{cb.chat_id}")
              Telegram::Helpers::Conversation.start(cb.chat_id, {
                "flow" => "create_game",
                "step" => "court",
                "fields" => saved_fields,
                "message_id" => resume_message_id
              })
              Telegram::Flows::Games::Manage::CreateFlow.send(:send_court_selection, cb.chat_id, 1, message_id: resume_message_id)
            else
              Telegram::Handlers::MenuHandler.menu(cb.chat_id, message_id: cb.message_id)
            end
            nil

          when /\Acourt:create:skip\z/
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            handle_skip(cb.chat_id, message_id: cb.message_id)
            nil

          when /\Acourt:create:contact_type:(.+)\z/
            ct = $1
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            process_contact_type(cb.chat_id, ct, message_id: cb.message_id)
            nil

          else
            nil
          end
        rescue => e
          Rails.logger.error "[CourtCreateFlow] handle_callback error: #{e.class} #{e.message}"
          nil
        end

        # Called by ReplyProcessor when flow == "create_court"
        def process_text(message)
          chat_id = (message.dig("chat", "id") || message.dig("from", "id")).to_s
          text = message["text"].to_s.strip
          conv = Telegram::Helpers::Conversation.get(chat_id)
          return false unless conv["flow"] == "create_court"
          delete_input_message(message)

          step = conv["step"]
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          case step
          when "name"
            if text.blank?
              Telegram::Api.send_simple(chat_id, t.(:create_court_name_invalid))
              return true
            end
            conv["fields"]["name"] = text
            save_and_advance(chat_id, conv, "name", message_id: conv["message_id"])

          when "location"
            # Try to parse as coordinates "lat,lon"
            coords = parse_coordinates(text)
            unless coords
              Telegram::Api.send_simple(chat_id, t.(:create_court_location_invalid))
              return true
            end
            conv["fields"]["coordinates"] = "#{coords[0]},#{coords[1]}"
            save_and_advance(chat_id, conv, "location", message_id: conv["message_id"])

          when "contact_value"
            conv["fields"]["contact_value"] = text
            save_and_advance(chat_id, conv, "contact_value", message_id: conv["message_id"])

          else
            Telegram::Api.send_simple(chat_id, t.(:please_use_buttons))
          end

          true
        rescue => e
          Rails.logger.error "[CourtCreateFlow] process_text error: #{e.class} #{e.message}"
          true
        end

        # Handle location message from Telegram (user shared location)
        def process_location(message)
          chat_id = (message.dig("chat", "id") || message.dig("from", "id")).to_s
          conv = Telegram::Helpers::Conversation.get(chat_id)
          return false unless conv["flow"] == "create_court" && conv["step"] == "location"

          location = message["location"]
          return false unless location
          delete_input_message(message)

          lat = location["latitude"]
          lon = location["longitude"]
          conv["fields"]["coordinates"] = "#{lat},#{lon}"
          save_and_advance(chat_id, conv, "location", message_id: conv["message_id"])
          true
        rescue => e
          Rails.logger.error "[CourtCreateFlow] process_location error: #{e.class} #{e.message}"
          true
        end

        private

        def step_number(step)
          ALL_STEPS.index(step).to_i + 1
        end

        def send_step_prompt(chat_id, step, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          header = t.(:create_court_step, step: step_number(step), total: TOTAL_STEPS)
          cancel_row = [ { text: t.(:cancel_btn), callback_data: "court:create:cancel" } ]

          case step
          when "name"
            text = build_step_text(chat_id, header, t.(:create_court_name))
            buttons = [ cancel_row ]
            send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)

          when "location"
            text = build_step_text(chat_id, header, t.(:create_court_location))
            send_or_edit_with_buttons(chat_id, text, [ cancel_row ], message_id: message_id)
            # Request location via reply keyboard
            resp = Telegram::Api.send_api("sendMessage", {
              chat_id: chat_id,
              text: t.(:create_court_location_btn),
              reply_markup: {
                keyboard: [
                  [ { text: t.(:create_court_location_btn), request_location: true } ]
                ],
                resize_keyboard: true,
                one_time_keyboard: true
              }
            })
            store_location_request_message_id(chat_id, resp)

          when "contact_type"
            delete_location_request_message(chat_id)
            text = build_step_text(chat_id, header, t.(:create_court_contact_type))
            ct_buttons = Court::CONTACT_TYPES.map do |ct|
              [ { text: ct.capitalize, callback_data: "court:create:contact_type:#{ct}" } ]
            end
            buttons = ct_buttons + [
              [ { text: t.(:skip_btn), callback_data: "court:create:skip" } ],
              cancel_row
            ]
            # Remove the reply keyboard
            remove_resp = Telegram::Api.send_api("sendMessage", {
              chat_id: chat_id,
              text: ".",
              reply_markup: { remove_keyboard: true }
            }) rescue nil
            send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
            remove_msg_id = remove_resp.is_a?(Hash) ? remove_resp.dig("result", "message_id") : nil
            Telegram::Api.delete_message(chat_id, remove_msg_id) if remove_msg_id

          when "contact_value"
            text = build_step_text(chat_id, header, t.(:create_court_contact_value))
            buttons = [
              [ { text: t.(:skip_btn), callback_data: "court:create:skip" } ],
              cancel_row
            ]
            send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
          end
        end

        def send_start_options(chat_id, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          text = t.(:create_court_start_options)
          buttons = [
            [ { text: t.(:create_in_bot), callback_data: "court:create:bot" } ],
            [ { text: t.(:create_on_website), url: "https://getcourt.co/courts/new" } ],
            [ { text: t.(:cancel_btn), callback_data: "court:create:cancel" } ]
          ]
          send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
        end

        def handle_skip(chat_id, message_id: nil)
          conv = Telegram::Helpers::Conversation.get(chat_id)
          step = conv["step"]
          if OPTIONAL_STEPS.include?(step)
            save_and_advance(chat_id, conv, step, message_id: message_id || conv["message_id"])
          end
        end

        def process_contact_type(chat_id, ct, message_id: nil)
          conv = Telegram::Helpers::Conversation.get(chat_id)
          conv["fields"]["contact_type"] = ct
          save_and_advance(chat_id, conv, "contact_type", message_id: message_id)
        end

        def save_and_advance(chat_id, conv, current_step, message_id: nil)
          idx = ALL_STEPS.index(current_step)
          next_step = idx ? ALL_STEPS[idx + 1] : nil

          if next_step
            conv["step"] = next_step
            conv["message_id"] = message_id if message_id
            Telegram::Helpers::Conversation.set(chat_id, conv)
            send_step_prompt(chat_id, next_step, message_id: conv["message_id"])
          else
            finalize_court(chat_id, conv)
          end
        end

        def finalize_court(chat_id, conv)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          fields = conv["fields"] || {}
          return_to = conv["return_to"]
          resume_message_id = conv["message_id"]

          Telegram::Helpers::Conversation.finish(chat_id)

          # Remove reply keyboard if it was shown
          Telegram::Api.send_api("sendMessage", {
            chat_id: chat_id,
            text: ".",
            reply_markup: { remove_keyboard: true }
          }) rescue nil

          court = Court.new(
            name: fields["name"],
            coordinates: fields["coordinates"],
            contact_type: fields["contact_type"],
            contact_value: fields["contact_value"],
            user_id: user.id,
            moderation_status: "approved"
          )

          if court.save
            Telegram::Api.send_simple(chat_id, t.(:create_court_success))

            if return_to == "game_create"
              # Restore saved game creation fields and resume at court step
              saved_fields = Rails.cache.read("tg:game_create_fields:#{chat_id}") || {}
              Rails.cache.delete("tg:game_create_fields:#{chat_id}")
              Telegram::Helpers::Conversation.start(chat_id, {
                "flow" => "create_game",
                "step" => "court",
                "fields" => saved_fields,
                "message_id" => resume_message_id
              })
              # Let user re-pick from courts including the new one
              Telegram::Flows::Games::Manage::CreateFlow.send(:send_court_selection, chat_id, 1, message_id: resume_message_id)
            else
              Telegram::Handlers::MenuHandler.menu(chat_id)
            end
          else
            Telegram::Api.send_simple(chat_id, t.(:create_court_error, error: court.errors.full_messages.join(", ")))
            Telegram::Handlers::MenuHandler.menu(chat_id)
          end
        rescue => e
          Rails.logger.error "[CourtCreateFlow] finalize_court error: #{e.class} #{e.message}"
          Telegram::Api.send_simple(chat_id, t.(:create_court_error, error: e.message)) rescue nil
        end

        def parse_coordinates(text)
          return nil if text.blank?
          parts = text.split(",").map(&:strip)
          return nil unless parts.size == 2
          lat = Float(parts[0]) rescue nil
          lon = Float(parts[1]) rescue nil
          return nil unless lat && lon
          return nil unless lat.between?(-90, 90) && lon.between?(-180, 180)
          [ lat, lon ]
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
          return unless conv["flow"] == "create_court"

          conv["message_id"] = new_message_id
          Telegram::Helpers::Conversation.set(chat_id, conv)
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
            { "name" => "Название", "coordinates" => "Координаты", "contact_type" => "Тип контакта", "contact_value" => "Контакт" }
          else
            { "name" => "Name", "coordinates" => "Coordinates", "contact_type" => "Contact type", "contact_value" => "Contact" }
          end

          lines = []
          lines << "#{labels["name"]}: #{fields["name"]}" if fields["name"].present?
          lines << "#{labels["coordinates"]}: #{fields["coordinates"]}" if fields["coordinates"].present?
          lines << "#{labels["contact_type"]}: #{fields["contact_type"]}" if fields["contact_type"].present?
          lines << "#{labels["contact_value"]}: #{fields["contact_value"]}" if fields["contact_value"].present?
          return nil if lines.empty?

          title = locale == "ru" ? "Введено:" : "Entered:"
          ([ title ] + lines).join("\n")
        end

        def delete_input_message(message)
          chat_id = (message.dig("chat", "id") || message.dig("from", "id"))
          message_id = message["message_id"]
          return unless chat_id && message_id

          Telegram::Api.delete_message(chat_id, message_id)
        rescue
          nil
        end

        def store_location_request_message_id(chat_id, resp)
          msg_id = resp.is_a?(Hash) ? resp.dig("result", "message_id") : nil
          return unless msg_id

          conv = Telegram::Helpers::Conversation.get(chat_id)
          return unless conv["flow"] == "create_court"

          conv["location_request_message_id"] = msg_id
          Telegram::Helpers::Conversation.set(chat_id, conv)
        rescue
          nil
        end

        def delete_location_request_message(chat_id)
          conv = Telegram::Helpers::Conversation.get(chat_id)
          msg_id = conv["location_request_message_id"]
          return unless msg_id

          Telegram::Api.delete_message(chat_id, msg_id) rescue nil
          conv.delete("location_request_message_id")
          Telegram::Helpers::Conversation.set(chat_id, conv)
        rescue
          nil
        end
      end
    end
  end
end
