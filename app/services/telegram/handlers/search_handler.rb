module Telegram
  module Handlers
    class SearchHandler
      PER_PAGE = 5

      class << self
        # Search menu (by name / nearby)
        def menu(chat_id)
          buttons = [
            [{ text: "Find courts by name", callback_data: "menu:search:by_name" }],
            [{ text: "Find nearby courts", callback_data: "menu:search:nearby" }]
          ]
          Telegram::Api.send_with_buttons(chat_id, "Search:", buttons)
        end

        # Prompt user to enter query (ForceReply)
        def request_search_query(chat_id, cb_id: nil)
          poller = Telegram::Poller.new
          poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil

          # mark conversation so ReplyProcessor will route the force-reply
          begin
            key = Telegram::Handlers::CallbackHandler.conv_key(chat_id)
            Rails.cache.write(key, { "flow" => "search_name", "created_at" => Time.current }, expires_in: 10.minutes)
          rescue => e
            Rails.logger.error "[Telegram::Handlers::SearchHandler] request_search_query: cache write failed for chat=#{chat_id}: #{e.class}: #{e.message}"
          end

          poller.send_api("sendMessage", {
            chat_id: chat_id,
            text: "Send search query (court name):",
            reply_markup: { force_reply: true, selective: true }
          }) rescue nil
        end

        # Search courts by name with pagination
        def search_by_name(chat_id, query, page = 1)
          page = page.to_i < 1 ? 1 : page.to_i
          offset = (page - 1) * PER_PAGE
          scope = Court.where("name ILIKE ?", "%#{query}%")
          total = scope.count
          pages = (total.to_f / PER_PAGE).ceil
          courts = scope.order("id ASC").offset(offset).limit(PER_PAGE)

          header = "Results for \"#{query}\" — page #{page}/#{[pages, 1].max}\n\n"
          body = courts.each_with_index.map { |c, i| "#{offset + i + 1}. #{c.name}" }.join("\n")
          body = "No results." if body.empty?

          buttons = courts.map { |c| [{ text: c.name, callback_data: "court:show:#{c.id}:#{page}" }] }

          nav = []
          nav << [{ text: "‹ Prev", callback_data: "search:by_name:#{CGI.escape(query)}:#{page - 1}" }] if page > 1
          nav << [{ text: "Next ›", callback_data: "search:by_name:#{CGI.escape(query)}:#{page + 1}" }] if page < pages
          buttons << nav unless nav.empty?

          Telegram::Api.send_with_buttons(chat_id, header + body, buttons)
        end

        # Ask for location and delegate to courts handler
        def request_nearby_location(chat_id, cb_id: nil)
          Telegram::Handlers::CourtsHandler.request_nearby_location(chat_id)
        end
      end
    end
  end
end
