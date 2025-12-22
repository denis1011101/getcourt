module Telegram
  class MessageHandler
    # handle incoming Telegram "message" updates (force-reply flows etc.)
    def self.handle(message)
      message = message.to_h if message.respond_to?(:to_h)
      chat_id = message.dig("chat", "id") || message.dig("from", "id")
      return unless chat_id

      key = "tg:conv:#{chat_id}"
      conv = Rails.cache.read(key) || {}

      # conversational flow to collect full statistics
      if conv["step"]
        text = message["text"].to_s.strip
        if text.blank?
          Api.send_force_reply(chat_id, conv["prompt"] || "Please reply.")
          return
        end

        # allow skipping a step
        if text.downcase == "skip"
          conv["fields"] ||= {}
          conv["fields"][conv["step"]] = nil
        else
          case conv["step"]
          when "singles_hours", "doubles_hours"
            unless text.match?(/\A\d+(\.\d+)?\z/)
              Api.send_force_reply(chat_id, "Please reply with a number like 1.5 or type 'skip'.")
              return
            end
            conv["fields"] ||= {}
            conv["fields"][conv["step"]] = text.to_f
          when "singles_games", "singles_wins", "doubles_games", "doubles_wins", "aces", "double_faults"
            unless text.match?(/\A\d+\z/)
              Api.send_force_reply(chat_id, "Please reply with an integer (0,1,2...) or type 'skip'.")
              return
            end
            conv["fields"] ||= {}
            conv["fields"][conv["step"]] = text.to_i
          when "first_serve_pct"
            unless text.match?(/\A\d+(\.\d+)?\z/) && text.to_f.between?(0, 100)
              Api.send_force_reply(chat_id, "Please reply with percent 0-100 (e.g. 62.5) or type 'skip'.")
              return
            end
            conv["fields"] ||= {}
            conv["fields"][conv["step"]] = text.to_f
          else
            Api.send_simple(chat_id, "Unexpected step, aborting.")
            Rails.cache.delete(key)
            return
          end
        end

        # advance to next step sequence
        steps = %w[
          singles_hours doubles_hours
          singles_games singles_wins
          doubles_games doubles_wins
          aces double_faults first_serve_pct
        ]
        idx = steps.index(conv["step"]) || -1
        next_step = steps[idx + 1]

        if next_step
          conv["step"] = next_step
          conv["prompt"] = prompt_for(next_step)
          Rails.cache.write(key, conv, expires_in: 2.hours)
          Api.send_force_reply(chat_id, conv["prompt"])
          return
        end

        # finished collecting — persist into PlayerStatistic
        fields = conv["fields"] || {}
        user = User.find_by(telegram_chat_id: chat_id.to_s) || User.find_by(telegram_chat_id: chat_id.to_i)
        unless user
          Api.send_simple(chat_id, "User not found — cannot record statistics.")
          Rails.cache.delete(key)
          return
        end

        ps = user.player_statistic || user.create_player_statistic!
        # accumulate / increment where appropriate
        ps.with_lock do
          ps.update!(
            singles_hours: (ps.singles_hours.to_f + (fields["singles_hours"].to_f)).round(2),
            doubles_hours: (ps.doubles_hours.to_f + (fields["doubles_hours"].to_f)).round(2),
            singles_sessions: ps.singles_sessions.to_i + 1,
            singles_games: ps.singles_games.to_i + fields["singles_games"].to_i,
            singles_wins: ps.singles_wins.to_i + fields["singles_wins"].to_i,
            singles_losses: ps.singles_losses.to_i + (fields["singles_games"].to_i - fields["singles_wins"].to_i),
            doubles_games: ps.doubles_games.to_i + fields["doubles_games"].to_i,
            doubles_wins: ps.doubles_wins.to_i + fields["doubles_wins"].to_i,
            doubles_losses: ps.doubles_losses.to_i + (fields["doubles_games"].to_i - fields["doubles_wins"].to_i),
            aces: ps.aces.to_i + fields["aces"].to_i,
            double_faults: ps.double_faults.to_i + fields["double_faults"].to_i,
            first_serve_percent: (fields["first_serve_pct"].nil? ? ps.first_serve_percent : fields["first_serve_pct"].to_f)
          )
        end

        Api.send_simple(chat_id, "Statistics recorded. Thank you.")
        Rails.cache.delete(key)
        return
      end

      # no active flow — ignore or log
      Rails.logger.info("[Telegram::MessageHandler] Unhandled message from #{chat_id}: #{message.keys}")
    rescue => e
      Rails.logger.error("[Telegram::MessageHandler] #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}")
      Api.send_simple(chat_id, "Processing error.") rescue nil
    end

    def self.prompt_for(step)
      case step
      when "singles_hours"
        "Please reply with singles hours (example: 1.5) or type 'skip'."
      when "doubles_hours"
        "Please reply with doubles hours (example: 1.5) or type 'skip'."
      when "singles_games"
        "How many singles games were played? (integer) or 'skip'."
      when "singles_wins"
        "How many singles wins? (integer) or 'skip'."
      when "doubles_games"
        "How many doubles games were played? (integer) or 'skip'."
      when "doubles_wins"
        "How many doubles wins? (integer) or 'skip'."
      when "aces"
        "Number of aces (integer) or 'skip'."
      when "double_faults"
        "Number of double faults (integer) or 'skip'."
      when "first_serve_pct"
        "First serve percent (0-100, e.g. 62.5) or 'skip'."
      else
        "Please reply."
      end
    end
  end
end
