module Telegram
  module Handlers
    class TournamentsCallbackHandler
      def self.process(callback_query)
        cb = Telegram::Helpers::CallbackData.parse(callback_query)
        return false unless cb.chat_id.present? && cb.data.present?

        Rails.logger.debug "[Telegram::Handlers::TournamentsCallbackHandler] data=#{cb.data.inspect} chat_id=#{cb.chat_id}"

        # Pagination handled by TournamentsHandler
        if cb.data =~ /\Amenu:tournaments:page:(\d+)\z/
          page = $1.to_i
          Telegram::Handlers::TournamentsHandler.list_page(cb.chat_id, page, message_id: cb.message_id) rescue nil
          return true
        end

        # Delegate all tournament-related callbacks to TournamentsFlow
        if cb.data.start_with?("tournament:")
          begin
            Telegram::Flows::TournamentsFlow.handle_callback(callback_query)
          rescue => e
            Rails.logger.error "[Telegram::Handlers::TournamentsCallbackHandler] flow error: #{e.class}: #{e.message}"
            Telegram::Api.answer_callback(cb.cb_id, "Flow error: #{e.message}", show_alert: true) rescue nil
            return false
          end
          return true
        end

        true
      rescue => e
        Rails.logger.error "[Telegram::Handlers::TournamentsCallbackHandler] process error: #{e.class}: #{e.message}"
        cb_id = callback_query["id"] rescue nil
        Telegram::Api.answer_callback(cb_id, "Tournaments callback error.", show_alert: true) rescue nil
        false
      end
    end
  end
end
