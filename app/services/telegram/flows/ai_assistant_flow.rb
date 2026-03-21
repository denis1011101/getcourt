require "timeout"

module Telegram
  module Flows
    class AiAssistantFlow
      MAX_MESSAGE_LENGTH = 4096

      class << self
        def handle_callback(callback_query)
          cb = Telegram::Helpers::CallbackData.parse(callback_query)
          locale = Telegram::Helpers::UserLookup.locale_for(cb.chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          case cb.data
          when "ai:snippet:find_opponent"
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            Telegram::Helpers::Conversation.update(cb.chat_id, "flow" => "ai_assistant", "message_id" => cb.message_id)
            respond(cb.chat_id, t.(:ai_snippet_find_opponent_prompt), locale: locale)
            true
          when "ai:snippet:find_court"
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            Telegram::Helpers::Conversation.update(cb.chat_id, "flow" => "ai_assistant", "message_id" => cb.message_id)
            respond(cb.chat_id, t.(:ai_snippet_find_court_prompt), locale: locale)
            true
          when "ai:snippet:find_coach"
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            Telegram::Helpers::Conversation.update(cb.chat_id, "flow" => "ai_assistant", "message_id" => cb.message_id)
            respond(cb.chat_id, t.(:ai_snippet_find_coach_prompt), locale: locale)
            true
          when "ai:back"
            Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
            Telegram::Helpers::Conversation.finish(cb.chat_id)
            Telegram::Handlers::MenuHandler.menu(cb.chat_id, message_id: cb.message_id)
            true
          else
            false
          end
        rescue => e
          Rails.logger.error "[Telegram::Flows::AiAssistantFlow] handle_callback error: #{e.class} #{e.message}"
          false
        end

        def process_text(message)
          chat_id = (message.dig("chat", "id") || message.dig("from", "id")).to_s
          conv = Telegram::Helpers::Conversation.get(chat_id) rescue {}
          return false unless conv["flow"] == "ai_assistant"

          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          text = message["text"].to_s.strip
          return false if text.blank?
          if text.start_with?("/")
            Telegram::Helpers::Conversation.finish(chat_id)
            return false
          end

          respond(chat_id, text, locale: locale)
          true
        rescue => e
          Rails.logger.error "[Telegram::Flows::AiAssistantFlow] process_text error: #{e.class} #{e.message}"
          Telegram::Api.send_simple(chat_id, fallback_answer(locale || Telegram::I18n::DEFAULT_LOCALE), parse_mode: nil) rescue nil
          true
        end

        private

        def respond(chat_id, text, locale:)
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          thinking_text = Telegram::I18n.t(:ai_thinking, locale: locale)
          thinking_response = Telegram::Api.send_simple(chat_id, thinking_text, parse_mode: nil)
          thinking_message_id = extract_message_id(thinking_response)

          answer = Ai::AssistantService.new(user).chat(text, locale: locale)
          answer = fallback_answer(locale) if answer.blank?
          deliver_answer(chat_id, answer, thinking_message_id: thinking_message_id)
        rescue RubyLLM::RateLimitError => e
          Rails.logger.error "[Telegram::Flows::AiAssistantFlow] rate limit: #{e.message}"
          deliver_answer(chat_id, Telegram::I18n.t(:ai_rate_limit, locale: locale), thinking_message_id: thinking_message_id)
        rescue Timeout::Error => e
          Rails.logger.error "[Telegram::Flows::AiAssistantFlow] respond timeout: #{e.class} #{e.message}"
          deliver_answer(chat_id, Telegram::I18n.t(:ai_timeout, locale: locale), thinking_message_id: thinking_message_id)
        rescue => e
          Rails.logger.error "[Telegram::Flows::AiAssistantFlow] respond error: #{e.class} #{e.message}"
          deliver_answer(chat_id, fallback_answer(locale), thinking_message_id: thinking_message_id)
        end

        def fallback_answer(locale)
          Telegram::I18n.t(:processing_error, locale: locale)
        end

        def deliver_answer(chat_id, answer, thinking_message_id:)
          chunks = split_message(answer.to_s)
          first_chunk = chunks.shift.to_s

          if thinking_message_id.present?
            Telegram::Api.edit_message_text(chat_id, thinking_message_id, first_chunk, parse_mode: nil)
          else
            Telegram::Api.send_simple(chat_id, first_chunk, parse_mode: nil)
          end

          chunks.each do |chunk|
            Telegram::Api.send_simple(chat_id, chunk, parse_mode: nil)
          end
        end

        def split_message(text)
          normalized = text.to_s.strip
          normalized = fallback_answer(Telegram::I18n::DEFAULT_LOCALE) if normalized.blank?

          chunks = []
          remaining = normalized.dup

          while remaining.length > MAX_MESSAGE_LENGTH
            slice = remaining.slice(0, MAX_MESSAGE_LENGTH)
            break_at = [ slice.rindex("\n"), slice.rindex(" ") ].compact.max
            break_at = MAX_MESSAGE_LENGTH unless break_at && break_at >= (MAX_MESSAGE_LENGTH / 2)

            chunks << remaining.slice!(0, break_at).strip
            remaining = remaining.lstrip
          end

          chunks << remaining unless remaining.blank?
          chunks
        end

        def extract_message_id(response)
          return unless response.is_a?(Hash)

          response.dig("result", "message_id")
        end
      end
    end
  end
end
