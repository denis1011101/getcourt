module Telegram
  module Helpers
    # Shared game date/time formatting extracted from GamesHandler and MessageHandler.
    # Both had identical copies of these methods.
    module GameFormatting
      # Returns "YYYY-MM-DD HH:MM" or "YYYY-MM-DD" for a game.
      def self.game_datetime(game)
        d = resolve_date(game)
        return nil unless d.present?

        t = resolve_time(game)

        date_str = d.respond_to?(:strftime) ? d.strftime("%Y-%m-%d") : d.to_s
        time_str = format_time_hhmm(t)

        time_str.present? ? "#{date_str} #{time_str}" : date_str
      end

      # Formats a time value (Time, String, nil) into "HH:MM" or nil.
      def self.format_time_hhmm(t)
        return nil if t.nil?
        return t.strftime("%H:%M") if t.respond_to?(:strftime)

        s = t.to_s.strip
        return nil if s.empty?

        parts = s.split(":")
        return nil if parts.size < 2

        hh = parts[0].to_i.to_s.rjust(2, "0")
        mm = parts[1].to_i.to_s.rjust(2, "0")
        "#{hh}:#{mm}"
      end

      # Extracts game title: title > sport > "Game"
      def self.game_title(game)
        if game.respond_to?(:has_attribute?) && game.has_attribute?(:title)
          game.title.to_s.strip.presence
        elsif game.respond_to?(:sport)
          game.sport.to_s.strip.presence
        end
      end

      # Coach mark for invitations/reminders: nil when the game has no coach.
      def self.coach_mark(game, locale: Telegram::I18n::DEFAULT_LOCALE)
        Telegram::I18n.t(:coach_with, locale: locale) if game.respond_to?(:with_coach?) && game.with_coach?
      end

      # Resolves date using the occurrence chain: display_date_for_show > next_date > date
      def self.resolve_date(game)
        if game.respond_to?(:display_date_for_show)
          game.display_date_for_show
        elsif game.respond_to?(:next_date)
          game.next_date
        elsif game.respond_to?(:date)
          game.date
        end
      end

      # Resolves time using: next_time > time
      def self.resolve_time(game)
        if game.respond_to?(:next_time)
          game.next_time
        elsif game.respond_to?(:time)
          game.time
        end
      end
    end
  end
end
