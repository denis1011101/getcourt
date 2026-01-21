require "cgi"

module Telegram
  module Flows
    class SearchFlow
      class << self
        def handle_callback(callback)
          data = (callback["data"] || "").to_s
          cb_id = callback["id"]
          from = callback["from"] || {}
          chat_id = (callback.dig("message","chat","id") || from["id"]).to_s
          poller = Telegram::Poller.new

          case data
          when /\Amenu:search:by_name\z/
            Telegram::Handlers::SearchHandler.request_search_query(chat_id, cb_id: cb_id)
            return
          when /\Amenu:search:nearby\z/
            Telegram::Handlers::SearchHandler.request_nearby_location(chat_id, cb_id: cb_id)
            poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
            return
          when /\Asearch:by_name:(.+):(\d+)\z/
            query = CGI.unescape($1)
            page = $2.to_i
            Telegram::Handlers::SearchHandler.search_by_name(chat_id, query, page)
            poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
            return
          else
            poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Unknown search action", show_alert: false }) rescue nil
            return
          end
        rescue => e
          Rails.logger.error "[Telegram::Flows::SearchFlow] callback error: #{e.class} #{e.message}"
        end
      end
    end
  end
end
