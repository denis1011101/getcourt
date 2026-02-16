require "cgi"

module Telegram
  module Flows
    class SearchFlow
      class << self
        def handle_callback(callback)
          cb = Telegram::Helpers::CallbackData.parse(callback)
          poller = Telegram::Poller.new

          case cb.data
          when /\Amenu:search:by_name\z/
            Telegram::Handlers::SearchHandler.request_search_query(cb.chat_id, cb_id: cb.cb_id)
            nil
          when /\Amenu:search:nearby\z/
            Telegram::Handlers::SearchHandler.request_nearby_location(cb.chat_id, cb_id: cb.cb_id)
            poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil
            nil
          when /\Asearch:by_name:(.+):(\d+)\z/
            query = CGI.unescape($1)
            page = $2.to_i
            Telegram::Handlers::SearchHandler.search_by_name(cb.chat_id, query, page)
            poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil
            nil
          else
            poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "Unknown search action", show_alert: false }) rescue nil
            nil
          end
        rescue => e
          Rails.logger.error "[Telegram::Flows::SearchFlow] callback error: #{e.class} #{e.message}"
        end
      end
    end
  end
end
