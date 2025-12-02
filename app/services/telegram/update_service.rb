module Telegram
  class UpdateService
    # Process single Telegram update. Uses Telegram::Poller#send_api for outgoing API calls.
    def self.process(update)
      Rails.logger.info "[BOT] UpdateService.process update_id=#{update['update_id'].inspect}"
      poller = Telegram::Poller.new # temporary instance only for send_api usage

      # callback_query (button presses)
      if (cq = update["callback_query"])
        Rails.logger.info "[BOT] UpdateService.callback_query=#{cq.inspect}"
        data = cq["data"].to_s
        from = cq["from"] || {}
        chat_id = from["id"]
        chat_hash = { "id" => chat_id, "username" => from["username"], "first_name" => from["first_name"] }

        if data =~ /\Amenu:games(?::page:(\d+))?\z/
          page = ($1 || 1).to_i
          res = Telegram::GameService.payload_for_page(chat_id: chat_id, page: page)
          poller.send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "Games", show_alert: false })
          poller.send_api("sendMessage", res[:payload])
          return
        end

        if data =~ /\Ajoin:(\d+)\z/
          game_id = $1.to_i
          ok, msg = Telegram::GameService.join_by_chat(chat_hash, game_id)
          poller.send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: msg, show_alert: false })
          poller.send_api("sendMessage", { chat_id: chat_id, text: msg })
          return
        end

        if data =~ /\Aleave:(\d+)\z/
          game_id = $1.to_i
          ok, msg = Telegram::GameService.leave_by_chat(chat_hash, game_id)
          poller.send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: msg, show_alert: false })
          poller.send_api("sendMessage", { chat_id: chat_id, text: msg })
          return
        end

        if data =~ /\Amenu:my_games(?::page:(\d+))?\z/
          page = ($1 || 1).to_i
          res = Telegram::GameService.payload_for_my_games(chat_id: chat_id, page: page)
          poller.send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "My Games", show_alert: false })
          poller.send_api("sendMessage", res[:payload])
          return
        end

        poller.send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "Unknown action", show_alert: false })
        return
      end

      # message handling (start/register/commands)
      message = update["message"] || {}
      chat = message["chat"] || {}
      text = message["text"].to_s.strip
      Rails.logger.info "[BOT] UpdateService message chat=#{chat.inspect} text=#{text.inspect}"

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
          Rails.logger.error "[BOT] UpdateService /start handling failed: #{e.class} #{e.message}"
        end
        return
      end

      if text =~ %r{\A/all_games(?:\s+(\d+))?\b}i
        page = ($1 || 1).to_i
        res = Telegram::GameService.payload_for_page(chat_id: chat["id"], page: page)
        Rails.logger.info "[BOT] /all_games page=#{page} meta=#{res[:meta].inspect}"
        poller.send_api("sendMessage", res[:payload])
        return
      end

      if text =~ %r{\A/my_games(?:\s+(\d+))?\b}i
        page = ($1 || 1).to_i
        res = Telegram::GameService.payload_for_my_games(chat_id: chat["id"], page: page)
        Rails.logger.info "[BOT] /my_games page=#{page} meta=#{res[:meta].inspect}"
        poller.send_api("sendMessage", res[:payload])
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
        return
      end

    rescue => e
      Rails.logger.error "Telegram.UpdateService error: #{e.class} #{e.message}"
    end
  end
end
