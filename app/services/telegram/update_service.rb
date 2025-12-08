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

        # invite callback — instruct owner how to send invites
        if data =~ /\Ainvite:(\d+)\z/
          game_id = $1.to_i
          owner = User.find_by(telegram_chat_id: chat_id.to_s)
          game = Game.find_by(id: game_id)
          if game && owner && game.user_id == owner.id
            poller.send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "Reply to the message with usernames to invite", show_alert: false })
            # include machine-readable marker INVITE_PROMPT so replies are unambiguous (no waiting)
            poller.send_api("sendMessage", {
              chat_id: chat_id,
              text: "INVITE_PROMPT game:#{game_id}\nPlease reply to this message with usernames to invite (e.g. @kisskatusha @john_doe). All usernames in your reply will be processed immediately.",
              reply_markup: { force_reply: true, selective: true }
            })
          else
            poller.send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "Only the game owner can invite", show_alert: false })
          end
          return
        end

        # create court flow (ForceReply)
        if data =~ /\Acreate_court\z/
          owner = User.find_by(telegram_chat_id: chat_id.to_s)
          if owner
            poller.send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "Reply to create a Court", show_alert: false })
            poller.send_api("sendMessage", {
              chat_id: chat_id,
              text: "COURT_PROMPT\nReply with court info in one line or multiple lines:\nName; lat,lon; contact_type:contact_value\nExample:\nCentral Court; 55.7558,37.6173; telegram:ivan123",
              reply_markup: { force_reply: true, selective: true }
            })
          else
            poller.send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "No linked account", show_alert: false })
          end
          return
        end

        # create game flow (ForceReply)
        if data =~ /\Acreate_game\z/
          owner = User.find_by(telegram_chat_id: chat_id.to_s)
          if owner
            poller.send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "Reply to create a Game", show_alert: false })
            poller.send_api("sendMessage", {
              chat_id: chat_id,
              text: "GAME_PROMPT\nReply with: court_id date(YYYY-MM-DD) time(HH:MM) players_count sport\nExample:\n3 2025-12-10 19:00 4 tennis",
              reply_markup: { force_reply: true, selective: true }
            })
          else
            poller.send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "No linked account", show_alert: false })
          end
          return
        end

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

        if data =~ /\Adecline:(\d+)\z/
          game_id = $1.to_i
          decliner = User.find_by(telegram_chat_id: chat_id.to_s)
          game = Game.find_by(id: game_id)
          # ack button for user
          poller.send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "You declined invite to game ##{game_id}", show_alert: false })
          poller.send_api("sendMessage", { chat_id: chat_id, text: "You declined invite to game ##{game_id}." })
          # notify owner if available
          if game && game.user && game.user.telegram_chat_id.present?
            owner_cid = game.user.telegram_chat_id
            name = decliner ? (decliner.name || decliner.email) : "A user"
            poller.send_api("sendMessage", { chat_id: owner_cid, text: "#{name} declined invite to game ##{game_id}." })
          end
          return
        end

        if data =~ /\Adelete:(\d+)\z/
          game_id = $1.to_i
          owner = User.find_by(telegram_chat_id: chat_id.to_s)
          game = Game.find_by(id: game_id)
          if game && owner && game.user_id == owner.id
            begin
              game.destroy!
              poller.send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "Game ##{game_id} deleted", show_alert: false })
              poller.send_api("sendMessage", { chat_id: chat_id, text: "Game ##{game_id} has been deleted." })
            rescue => e
              Rails.logger.error "[BOT] UpdateService delete error: #{e.class} #{e.message}"
              poller.send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "Failed to delete game (server error).", show_alert: false })
            end
          else
            poller.send_api("answerCallbackQuery", { callback_query_id: cq["id"], text: "Only the game owner can delete", show_alert: false })
          end
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

      # If this is a reply to our INVITE_PROMPT, convert to immediate /invite processing
      if message["reply_to_message"] && (rt = message["reply_to_message"]["text"].to_s) =~ /\AINVITE_PROMPT game:(\d+)\b/
        game_id = $1.to_i
        # convert the user's reply into the same format as /invite <game_id> <handles>
        text = "/invite #{game_id} #{text}"
        Rails.logger.info "[BOT] UpdateService converted reply -> #{text}"
      end

      # COURT_PROMPT -> /create_court <payload>
      if message["reply_to_message"] && (rt = message["reply_to_message"]["text"].to_s) =~ /\ACOURT_PROMPT\b/
        text = "/create_court #{text}"
        Rails.logger.info "[BOT] UpdateService converted court reply -> #{text}"
      end

      # GAME_PROMPT -> /create_game <payload>
      if message["reply_to_message"] && (rt = message["reply_to_message"]["text"].to_s) =~ /\AGAME_PROMPT\b/
        text = "/create_game #{text}"
        Rails.logger.info "[BOT] UpdateService converted game reply -> #{text}"
      end

      # If there is a pending invite collection for this chat, collect lines or handle /done
      pending_key = "tg:pending_invite:#{chat['id']}"
      if Rails.cache.exist?(pending_key) && !(text =~ %r{\A/invite\b}i)
        pending = Rails.cache.read(pending_key) || {}
        # /done — process accumulated handles
        if text =~ %r{\A/done\b}i
          handles = Array(pending[:handles]).uniq
          Rails.cache.delete(pending_key)
          # reuse existing /invite processing logic by building a fake command text
          fake = "/invite #{pending[:game_id]} #{handles.map { |h| '@'+h }.join(' ')}"
          text = fake
        else
          # collect handles from this message and save, then ack
          found = text.scan(/@[\w\d_]+/i).map { |h| h.sub('@','').downcase }
          pending[:handles] = Array(pending[:handles]) | found
          Rails.cache.write(pending_key, pending, expires_in: 10.minutes)
          poller.send_api("sendMessage", { chat_id: chat['id'], text: "Added #{found.map{|h| "@#{h}"}.join(', ')}. Send more or /done to finish." })
          return
        end
      end

      # /invite GAME_ID @user1 @user2 ...
      if text =~ %r{\A/invite\s+(\d+)\s+(.+)}i
        game_id = $1.to_i
        raw = $2.to_s
        # immediate feedback
        poller.send_api("sendMessage", { chat_id: chat["id"], text: "Processing invitations..." })
        handles = raw.scan(/@[\w\d_]+/i).map { |h| h.sub('@','').downcase }.uniq
        if handles.empty?
          poller.send_api("sendMessage", { chat_id: chat["id"], text: "No usernames found. Use: /invite #{game_id} @user1 @user2" })
          return
        end

        inviter = User.find_by(telegram_chat_id: chat["id"].to_s)
        game = Game.find_by(id: game_id)
        unless inviter && game && game.user_id == inviter.id
          poller.send_api("sendMessage", { chat_id: chat["id"], text: "Only the game owner can send invites." })
          return
        end

        not_found = []
        skipped_self = []

        # Build mapping username -> user by asking Telegram getChat for each stored chat_id.
        username_map = {}
        chatid_map = {}
        User.where("telegram_chat_id IS NOT NULL AND telegram_chat_id != ''").find_each do |u|
          cid = u.telegram_chat_id.to_s
          begin
            res = poller.send_api("getChat", { chat_id: cid })
            if res && res.respond_to?(:body)
              data = JSON.parse(res.body) rescue nil
              nick = data.dig("result", "username")&.downcase if data && data["ok"]
              username_map[nick] = u if nick.present?
            end
          rescue => _e
            # ignore per-user failures (bot may be blocked / chat deleted)
          end
          chatid_map[cid] = u
        end

        handles.each do |uname|
          # match by username (preferred) or by chat_id string if user provided numeric/chat id
          user = username_map[uname] || chatid_map[uname]

          # If we couldn't resolve the username via DB+getChat, check if it's the inviter's own username/chat id.
          if user.nil? || user.telegram_chat_id.blank?
            inviter_username = chat["username"].to_s.downcase
            inviter_chatid_str = inviter&.telegram_chat_id.to_s
            if inviter && (uname == inviter_username || uname == inviter_chatid_str)
              skipped_self << "@#{uname}"
              next
            end

            not_found << "@#{uname}"
            next
          end

          # If resolved user is inviter -> skip with specific message
          if inviter && user.id == inviter.id
            skipped_self << "@#{uname}"
            next
          end

          invite_text = "You are invited to join game *##{game.id}* (#{game.sport.to_s.titleize}) by #{inviter.name || inviter.email}.\n\n#{Telegram::GameService.game_card(game)}"
           payload = {
            chat_id: user.telegram_chat_id,
            text: invite_text,
            parse_mode: "Markdown",
            reply_markup: { inline_keyboard: [[
              { text: "Join ##{game.id}", callback_data: "join:#{game.id}" },
              { text: "Decline ##{game.id}", callback_data: "decline:#{game.id}" }
            ]] }
           }
           poller.send_api("sendMessage", payload)
         end

        if not_found.empty? && skipped_self.empty?
          summary = "Invitations sent."
        elsif not_found.any? && skipped_self.empty?
          summary = "Invitations processed. Users not found: #{not_found.join(', ')}. Not found users must open @GetCourtBot and press /start to create or link their account."
        elsif skipped_self.any? && not_found.empty?
          summary = "You tried to invite yourself (#{skipped_self.join(', ')}); skipped. To join your own game, press \"Join ##{game.id}\" in the game list or send /join #{game.id}."
        else
          summary = "Invitations processed. Users not found: #{not_found.join(', ')}. You tried to invite yourself (#{skipped_self.join(', ')}); skipped. Not found users must open @GetCourtBot and press /start to create or link their account."
        end
        poller.send_api("sendMessage", { chat_id: chat["id"], text: summary })
         return
      end

      # if user sent bare /create_court -> prompt with ForceReply
      if text =~ %r{\A/create_court\b}i && !(text =~ %r{\A/create_court\s+(.+)}i)
        inviter = User.find_by(telegram_chat_id: chat["id"].to_s)
        unless inviter
          poller.send_api("sendMessage", { chat_id: chat["id"], text: "No linked account. Send /start first." })
          return
        end
        poller.send_api("sendMessage", {
          chat_id: chat["id"],
          text: "COURT_PROMPT\nReply with court info in one line or multiple lines:\nName; lat,lon; contact_type:contact_value\nExample:\nCentral Court; 55.7558,37.6173; telegram:ivan123",
          reply_markup: { force_reply: true, selective: true }
        })
        return
      end

      # if user sent bare /create_game -> prompt with ForceReply
      if text =~ %r{\A/create_game\b}i && !(text =~ %r{\A/create_game\s+(.+)}i)
        inviter = User.find_by(telegram_chat_id: chat["id"].to_s)
        unless inviter
          poller.send_api("sendMessage", { chat_id: chat["id"], text: "No linked account. Send /start first." })
          return
        end
        poller.send_api("sendMessage", {
          chat_id: chat["id"],
          text: "GAME_PROMPT\nReply with: court_id date(YYYY-MM-DD) time(HH:MM) players_count sport\nExample:\n3 2025-12-10 19:00 4 tennis",
          reply_markup: { force_reply: true, selective: true }
        })
        return
      end

      # /create_court Name; lat,lon; contact_type:contact_value
      if text =~ %r{\A/create_court\s+(.+)}i
        payload = $1.to_s.strip
        inviter = User.find_by(telegram_chat_id: chat["id"].to_s)
        unless inviter
          poller.send_api("sendMessage", { chat_id: chat["id"], text: "No linked account. Send /start first." })
          return
        end

        # parse: allow semicolon-separated or newline
        parts = payload.split(/\s*;\s*/).map(&:strip)
        name = parts[0].presence || "Unnamed court"
        coords = parts[1].to_s.strip
        contact = parts[2].to_s.strip

        court = Court.new(name: name, user: inviter)
        court.coordinates = coords if coords.present?
        if contact.present? && contact.include?(":")
          ct, cv = contact.split(":", 2).map(&:strip)
          court.contact_type = ct
          court.contact_value = cv
        end

        if court.save
          poller.send_api("sendMessage", { chat_id: chat["id"], text: "Court created: ##{court.id} #{court.name}" })
        else
          poller.send_api("sendMessage", { chat_id: chat["id"], text: "Failed to create court: #{court.errors.full_messages.join(', ')}" })
        end
        return
      end

      # /create_game court_id date time players_count sport
      if text =~ %r{\A/create_game\s+(.+)}i
        payload = $1.to_s.strip
        inviter = User.find_by(telegram_chat_id: chat["id"].to_s)
        unless inviter
          poller.send_api("sendMessage", { chat_id: chat["id"], text: "No linked account. Send /start first." })
          return
        end

        parts = payload.split(/\s+/)
        if parts.size < 4
          poller.send_api("sendMessage", { chat_id: chat["id"], text: "Invalid format. Use: /create_game court_id date time players_count sport" })
          return
        end
        court_id = parts[0].to_i
        date_str = parts[1]
        time_str = parts[2]
        players_count = parts[3].to_i
        sport = parts[4..].join(" ").presence || "unspecified"

        game = Game.new(court_id: court_id, user: inviter, date: date_str.presence, time: time_str.presence, players_count: players_count, sport: sport)
        if game.save
          poller.send_api("sendMessage", { chat_id: chat["id"], text: "Game created: ##{game.id}\n#{Telegram::GameService.game_card(game)}" })
        else
          poller.send_api("sendMessage", { chat_id: chat["id"], text: "Failed to create game: #{game.errors.full_messages.join(', ')}" })
        end
        return
      end

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
