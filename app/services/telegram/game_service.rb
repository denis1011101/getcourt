module Telegram
  class GameService
    DEFAULT_PER_PAGE = 5

    # Формирует короткую текстовую карточку для одной игры
    def self.game_card(game)
      # use next_date/next_time so recurring games show next occurrence
      date = (game.next_date || game.date)&.strftime("%Y-%m-%d") || "—"
      time = if (t = game.next_time || game.time)
               (t.respond_to?(:strftime) ? t.strftime("%H:%M") : t.to_s)
             else
               "—"
             end

      total = if game.respond_to?(:players_count) && game.players_count.present?
                game.players_count.to_i
              else
                (game.participations.size + 4)
              end
      taken = game.participations.size
      left = [total - taken, 0].max

      [
        "*##{game.id}* — #{game.sport.to_s.titleize}",
        "Date: #{date} #{time}",
        "Spots: #{left} left (#{taken}/#{total})",
        "Owner: #{game.user&.name || '—'}"
      ].join("\n")
    end

    # Возвращает ActiveRecord::Relation для страницы
    def self.page_of_games(page: 1, per_page: DEFAULT_PER_PAGE)
      # keep behaviour but sort by next_date/next_time in Ruby to account for recurring
      all = Game.all.to_a
      sorted = all.sort_by do |g|
        nd = g.next_date || Date.new(9999,1,1)
        nt = g.next_time || Time.new(0)
        [nd, nt]
      end
      page = page.to_i < 1 ? 1 : page.to_i
      offset = (page - 1) * per_page
      sorted.slice(offset, per_page) || []
    end

    # Возвращает общее количество страниц
    def self.total_pages(per_page: DEFAULT_PER_PAGE)
      total = Game.count
      [ (total.to_f / per_page).ceil, 1 ].max
    end

    # Подготовить payload для отправки одной страницы игр (inline клавиатура + текст)
    # Возвращает Hash с ключами :payload (ready for send_api) и :meta (page info)
    def self.payload_for_page(chat_id:, page: 1, per_page: DEFAULT_PER_PAGE)
      page = page.to_i < 1 ? 1 : page.to_i
      per_page = per_page.to_i <= 0 ? DEFAULT_PER_PAGE : per_page.to_i

      # load games and sort by next occurrence so recurring games appear with updated dates
      base = Game.all.to_a
      if chat_id.present?
        user = User.find_by(telegram_chat_id: chat_id.to_s)
        if user
          base.reject! { |g| user.participations.map(&:game_id).include?(g.id) }
        end
      end

      sorted = base.sort_by do |g|
        nd = g.next_date || Date.new(9999,1,1)
        nt = g.next_time || Time.new(0)
        [nd, nt]
      end

      total = sorted.size
      total_pages = [ (total.to_f / per_page).ceil, 1 ].max
      page = [[page, 1].max, total_pages].min
      offset = (page - 1) * per_page
      games = sorted.slice(offset, per_page) || []

      if games.empty?
        payload = {
          chat_id: chat_id.to_s,
          text: "No upcoming games found."
        }
        return { payload: payload, meta: { page: page, total_pages: total_pages } }
      end

      lines = games.map { |g| game_card(g) }
      btn_rows = games.map { |g| [{ text: "Join ##{g.id}", callback_data: "join:#{g.id}" }] }

      nav_buttons = []
      nav_buttons << { text: "« Prev", callback_data: "menu:games:page:#{page - 1}" } if page > 1
      nav_buttons << { text: "Next »", callback_data: "menu:games:page:#{page + 1}" } if page < total_pages
      btn_rows << nav_buttons unless nav_buttons.empty?

      payload = {
        chat_id: chat_id.to_s,
        text: lines.join("\n\n"),
        parse_mode: "Markdown",
        reply_markup: { inline_keyboard: btn_rows }
      }

      { payload: payload, meta: { page: page, total_pages: total_pages } }
    end

    # Попытка вступить в игру по chat_hash и game_id
    # Возвращает [boolean success, String message]
    def self.join_by_chat(chat_hash, game_id)
      chat_id = chat_hash['id'].to_s
      user = User.find_by(telegram_chat_id: chat_id)
      return [false, "No account linked to this Telegram. Send /start to create or /register <token> to link."] unless user

      game = Game.find_by(id: game_id)
      return [false, "Game ##{game_id} not found."] unless game

      participation = game.participations.build(user: user)
      begin
        participation.save!
        # уведомить владельца через нотификатор, если он есть
        Telegram::ParticipationNotifier.notify_owner(game, user, action: :joined) rescue nil
        [true, "You joined game ##{game.id}. Owner: #{game.user&.name || '—'}"]
      rescue ActiveRecord::RecordNotUnique
        [false, "You already joined game ##{game.id}."]
      rescue ActiveRecord::RecordInvalid => e
        [false, "Failed to join: #{e.record.errors.full_messages.join(', ')}"]
      rescue => e
        Rails.logger.error "[BOT] GameService.join_by_chat error: #{e.class} #{e.message}"
        [false, "Internal error while joining. Try later."]
      end
    end

    # Подготовить payload для отправки игр пользователя (в которых он участвует) с кнопками Leave
    def self.payload_for_my_games(chat_id:, page: 1, per_page: DEFAULT_PER_PAGE)
      page = page.to_i < 1 ? 1 : page.to_i
      per_page = per_page.to_i <= 0 ? DEFAULT_PER_PAGE : per_page.to_i

      user = User.find_by(telegram_chat_id: chat_id.to_s)
      unless user
        payload = { chat_id: chat_id.to_s, text: "No account linked. Send /start to create or /register <token>." }
        return { payload: payload, meta: { page: 1, total_pages: 0 } }
      end

      # игры, в которых пользователь участвует И/ИЛИ которые он создал
      # include owned games and games where he participates
      base = Game.where(user_id: user.id)
                 .or(Game.where(id: user.participations.select(:game_id)))
                 .order(:date).distinct

      total = base.count
      total_pages = [ (total.to_f / per_page).ceil, 1 ].max
      page = [[page, 1].max, total_pages].min
      offset = (page - 1) * per_page
      games = base.offset(offset).limit(per_page)

      if games.empty?
        payload = { chat_id: chat_id.to_s, text: "You haven't joined any games yet. Use /all_games to browse." }
        return { payload: payload, meta: { page: page, total_pages: total_pages } }
      end

      lines = games.map { |g| game_card(g) }

      btn_rows = games.map do |g|
        # treat as owner either by user_id OR by matching owner's telegram_chat_id to caller chat_id
        if g.user_id == user.id || (g.user&.telegram_chat_id.to_s == chat_id.to_s)
          # compute game datetime (date + optional time)
          game_time = begin
            if g.respond_to?(:date) && g.date.present?
              if g.respond_to?(:time) && g.time.present?
                DateTime.parse("#{g.date} #{g.time}")
              else
                g.date.to_datetime
              end
            else
              nil
            end
          rescue => _e
            nil
          end

          # compute available spots (same logic as game_card)
          total = if g.respond_to?(:players_count) && g.players_count.present?
                    g.players_count.to_i
                  else
                    (g.participations.size + 4)
                  end
          taken = g.participations.size
          left = [total - taken, 0].max

          # build buttons row: Invite (if future + spots), Join/Leave and Delete for owner
          buttons = []
          buttons << { text: "Invite ##{g.id}", callback_data: "invite:#{g.id}" } if (game_time.nil? || game_time > Time.current) && left > 0

          if g.participations.exists?(user_id: user.id)
            buttons << { text: "Leave ##{g.id}", callback_data: "leave:#{g.id}" }
          else
            buttons << { text: "Join ##{g.id}", callback_data: "join:#{g.id}" }
          end

          # allow owner to delete the game (confirmation should be handled in callback handling)
          buttons << { text: "Delete ##{g.id}", callback_data: "delete:#{g.id}" }

          buttons.empty? ? nil : buttons
        else
          [{ text: "Leave ##{g.id}", callback_data: "leave:#{g.id}" }]
        end
      end.compact

      nav_buttons = []
      nav_buttons << { text: "« Prev", callback_data: "menu:my_games:page:#{page - 1}" } if page > 1
      nav_buttons << { text: "Next »", callback_data: "menu:my_games:page:#{page + 1}" } if page < total_pages
      btn_rows << nav_buttons unless nav_buttons.empty?

      payload = {
        chat_id: chat_id.to_s,
        text: lines.join("\n\n"),
        parse_mode: "Markdown",
        reply_markup: { inline_keyboard: btn_rows }
      }

      { payload: payload, meta: { page: page, total_pages: total_pages } }
    end

    # Попытка выйти из игры по chat_hash и game_id
    def self.leave_by_chat(chat_hash, game_id)
      chat_id = chat_hash['id'].to_s
      user = User.find_by(telegram_chat_id: chat_id)
      return [false, "No account linked to this Telegram. Send /start to create or /register <token> to link."] unless user

      game = Game.find_by(id: game_id)
      return [false, "Game ##{game_id} not found."] unless game

      participation = game.participations.find_by(user: user)
      return [false, "You are not participating in game ##{game_id}."] unless participation

      begin
        participation.destroy!
        # уведомить владельца, если нужно
        Telegram::ParticipationNotifier.notify_owner(game, user, action: :left) rescue nil
        [true, "You left game ##{game.id}."]
      rescue => e
        Rails.logger.error "[BOT] GameService.leave_by_chat error: #{e.class} #{e.message}"
        [false, "Internal error while leaving. Try later."]
      end
    end
  end
end
