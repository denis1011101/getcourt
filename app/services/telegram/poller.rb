require "net/http"
require "json"

module Telegram
  class Poller
    API_ROOT = ->(token) { "https://api.telegram.org/bot#{token}" }

    def initialize(token: ENV["TELEGRAM_BOT_TOKEN"])
      @token = token.to_s
      raise "TELEGRAM_BOT_TOKEN not set" if @token.strip.empty?
      @api = API_ROOT.call(@token)
      @offset = nil
    end

    # Run single poll iteration (useful for tests)
    def run_once
      uri = URI("#{@api}/getUpdates")
      params = { timeout: 0 }
      params[:offset] = @offset if @offset
      uri.query = URI.encode_www_form(params)

      res = Net::HTTP.get_response(uri)
      return unless res.is_a?(Net::HTTPSuccess)

      data = JSON.parse(res.body) rescue {}
      (data["result"] || []).each do |update|
        Telegram::UpdateService.process(update)
        @offset = update["update_id"].to_i + 1
      end
    rescue => e
      Rails.logger.error "Telegram poll error: #{e.class} #{e.message}"
    end

    # Blocking loop (run locally)
    def run_loop(poll_interval: 1)
      loop do
        run_once
        sleep poll_interval
      end
    end

    # Отправка JSON запроса к Telegram API
    def send_api(method, payload = {})
      uri = URI("#{@api}/#{method}")
      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req.body = payload.to_json
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(req)
      end
    rescue => e
      Rails.logger.error "[BOT] send_api #{method} error: #{e.class} #{e.message}"
      nil
    end

    private

    # Duplicate small part of BotWebhookController logic to handle /register commands
     def process_update(update)
      Rails.logger.info "[BOT] Poller.process_update update_id=#{update['update_id'].inspect}"

      # callback_query (button presses)
      if (cq = update["callback_query"])
        Rails.logger.info "[BOT] Poller.callback_query=#{cq.inspect}"
        data = cq["data"].to_s
        from = cq["from"] || {}
        chat_id = from["id"]
        chat_hash = { "id" => chat_id, "username" => from["username"], "first_name" => from["first_name"] }

        # menu:games or paginated menu:games:page:N
        if data =~ /\Amenu:games(?::page:(\d+))?\z/
          page = ($1 || 1).to_i
          res = Telegram::GameService.payload_for_page(chat_id: chat_id, page: page)
          send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "Games", show_alert: false })
          # payload_for_page returns payload ready for sendMessage
          send_api("sendMessage", res[:payload])
          return
        end

        # join callback
        if data =~ /\Ajoin:(\d+)\z/
          game_id = $1.to_i
          ok, msg = Telegram::GameService.join_by_chat(chat_hash, game_id)
          send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: msg, show_alert: false })
          send_api("sendMessage", { chat_id: chat_id, text: msg })
          return
        end

      # leave callback
      if data =~ /\Aleave:(\d+)\z/
        game_id = $1.to_i
        ok, msg = Telegram::GameService.leave_by_chat(chat_hash, game_id)
        send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: msg, show_alert: false })
        send_api("sendMessage", { chat_id: chat_id, text: msg })
        return
      end

      # decline callback — notify owner that invite was declined
      if data =~ /\Adecline:(\d+)\z/
        game_id = $1.to_i
        decliner = User.find_by(telegram_chat_id: chat_id.to_s)
        game = Game.find_by(id: game_id)
        send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "You declined invite to game ##{game_id}", show_alert: false })
        send_api("sendMessage", { chat_id: chat_id, text: "You declined invite to game ##{game_id}." })
        if game && game.user && game.user.telegram_chat_id.present?
          name = decliner ? (decliner.name || decliner.email) : "A user"
          send_api("sendMessage", { chat_id: game.user.telegram_chat_id, text: "#{name} declined invite to game ##{game_id}." })
        end
        return
      end

      # delete callback (owner only)
      if data =~ /\Adelete:(\d+)\z/
        game_id = $1.to_i
        owner = User.find_by(telegram_chat_id: chat_id.to_s)
        game = Game.find_by(id: game_id)
        if game && owner && game.user_id == owner.id
          begin
            game.destroy!
            send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "Game ##{game_id} deleted", show_alert: false })
            send_api("sendMessage", { chat_id: chat_id, text: "Game ##{game_id} has been deleted." })
          rescue => e
            Rails.logger.error "[BOT] Poller.delete error: #{e.class} #{e.message}"
            send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "Failed to delete game (server error).", show_alert: false })
          end
        else
          send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "Only the game owner can delete", show_alert: false })
        end
        return
      end

      # manage: show per-participant Remove buttons (owner only)
      if data =~ /\Amanage:(\d+)\z/
        game_id = $1.to_i
        owner = User.find_by(telegram_chat_id: chat_id.to_s)
        game = Game.includes(participations: :user).find_by(id: game_id)
        if game && owner && game.user_id == owner.id
          participants = game.participations.map(&:user).compact.reject { |u| u.id == owner.id }
          if participants.empty?
            send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "No other participants to manage", show_alert: false })
            send_api("sendMessage", { chat_id: chat_id, text: "No other participants to manage for game ##{game_id}." })
          else
            rows = participants.map do |p|
              [{ text: "Remove #{p.name || p.email}", callback_data: "remove:#{game.id}:#{p.id}" }]
            end
            send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "Manage players", show_alert: false })
            send_api("sendMessage", { chat_id: chat_id, text: "Participants for game ##{game_id}:", reply_markup: { inline_keyboard: rows } })
          end
        else
          send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "Only the game owner can manage players", show_alert: false })
        end
        return
      end

      # remove: owner removes participant
      if data =~ /\Aremove:(\d+):(\d+)\z/
        game_id = $1.to_i
        target_user_id = $2.to_i
        owner = User.find_by(telegram_chat_id: chat_id.to_s)
        game = Game.find_by(id: game_id)
        if game && owner && game.user_id == owner.id
          participation = game.participations.find_by(user_id: target_user_id)
          if participation
            target = participation.user
            begin
              participation.destroy!
              send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "Removed #{target&.name || 'user'} from ##{game_id}", show_alert: false })
              send_api("sendMessage", { chat_id: chat_id, text: "User #{target&.name || target&.email || target_user_id} removed from game ##{game_id}." })
              if target && target.telegram_chat_id.present?
                send_api("sendMessage", { chat_id: target.telegram_chat_id, text: "You have been removed from game ##{game_id} by the owner." })
              end
            rescue => e
              Rails.logger.error "[BOT] UpdateService remove error: #{e.class} #{e.message}"
              send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "Failed to remove player (server error)", show_alert: false })
            end
          else
            send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "Player not found in this game", show_alert: false })
          end
        else
          send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "Only the game owner can remove players", show_alert: false })
        end
        return
      end

      # my_games pagination callback
      if data =~ /\Amenu:my_games(?::page:(\d+))?\z/
        page = ($1 || 1).to_i
        res = Telegram::GameService.payload_for_my_games(chat_id: chat_id, page: page)
        send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "My Games", show_alert: false })
        send_api("sendMessage", res[:payload])
        return
      end

        send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "Unknown action", show_alert: false })
        return
      end

      message = update["message"] || {}
      chat = message["chat"] || {}
      text = message["text"].to_s.strip
      Rails.logger.info "[BOT] Poller message chat=#{chat.inspect} text=#{text.inspect}"

      # handle /start for polling mode (create/link user)
      if text =~ %r{\A/start\b}i
        begin
          user, created = Telegram::UserService.find_or_create_for_chat(chat)
          chat_id = chat["id"].to_s
          if created
            TelegramNotifier.send_message(chat_id, "Welcome! Created account #{user.email}. You can manage it on the site.")
            TelegramNotifier.send_message(chat_id, "To link an existing account, generate a registration token on the site and send: /register <token>")
          else
            TelegramNotifier.send_message(chat_id, "Hello #{user.name || user.email}. Your Telegram is linked to this account.")
          end
        rescue => e
          Rails.logger.error "[BOT] Poller /start handling failed: #{e.class} #{e.message}"
        end
        return
      end

      # /all_games — show paginated list of available games (excluding user's participations)
      if text =~ %r{\A/all_games(?:\s+(\d+))?\b}i
        page = ($1 || 1).to_i
        res = Telegram::GameService.payload_for_page(chat_id: chat["id"], page: page)
        Rails.logger.info "[BOT] /all_games page=#{page} meta=#{res[:meta].inspect}"
        send_api("sendMessage", res[:payload])
        return
      end

      # /my_games — show user's joined games with Leave buttons
      if text =~ %r{\A/my_games(?:\s+(\d+))?\b}i
        page = ($1 || 1).to_i
        res = Telegram::GameService.payload_for_my_games(chat_id: chat["id"], page: page)
        Rails.logger.info "[BOT] /my_games page=#{page} meta=#{res[:meta].inspect}"
        send_api("sendMessage", res[:payload])
        return
      end

      if text =~ %r{\A/register\s+([0-9a-fA-F]+)\z}i
        token = $1
        user = User.find_by(telegram_registration_token: token)
        if user && chat["id"]
          chat_id = chat["id"].to_s
          User.transaction do
            User.where(telegram_chat_id: chat_id).where.not(id: user.id).update_all(telegram_chat_id: nil)
            user.update!(telegram_chat_id: chat_id)
            user.clear_telegram_registration_token! rescue nil
          end
          TelegramNotifier.send_message(chat_id, "Registration complete. You will receive notifications here.")
        else
          TelegramNotifier.send_message(chat["id"], "Invalid or expired token.") if chat["id"]
        end
      end
    rescue => e
      Rails.logger.error "Telegram.process_update error: #{e.class} #{e.message}"
    end
  end
end
