module Telegram
  module Helpers
    module GameFormatting
      def self.game_datetime(game, locale: Telegram::I18n::DEFAULT_LOCALE)
        date = resolve_date(game)
        return nil unless date.present?

        time = resolve_time(game)
        date_text = date.respond_to?(:strftime) ? ::I18n.l(date, format: :telegram, locale: locale) : date.to_s
        time_text = format_time_hhmm(time, locale: locale)
        time_text.present? ? "#{date_text} #{time_text}" : date_text
      end

      def self.format_time_hhmm(time, locale: Telegram::I18n::DEFAULT_LOCALE)
        return nil if time.nil?
        return ::I18n.l(time, format: :telegram, locale: locale) if time.respond_to?(:strftime)

        value = time.to_s.strip
        return nil if value.empty?

        parts = value.split(":")
        return nil if parts.size < 2

        "#{parts[0].to_i.to_s.rjust(2, "0")}:#{parts[1].to_i.to_s.rjust(2, "0")}"
      end

      def self.game_title(game, locale: Telegram::I18n::DEFAULT_LOCALE)
        if game.respond_to?(:has_attribute?) && game.has_attribute?(:title)
          game.title.to_s.strip.presence
        elsif game.respond_to?(:sport)
          sport_label(game.sport, locale: locale)
        end
      end

      def self.sport_label(sport, locale: Telegram::I18n::DEFAULT_LOCALE)
        value = sport.to_s.strip
        return nil if value.blank?

        key = "sport_#{value.downcase.tr(" ", "_")}"
        label = Telegram::I18n.t(key, locale: locale)
        label == key ? value : label
      end

      def self.skill_level_label(level, locale: Telegram::I18n::DEFAULT_LOCALE)
        value = level.to_s.strip
        return Telegram::I18n.t(:skill_any, locale: locale) if value.blank?

        key = "skill_#{value.downcase.tr(" ", "_")}"
        label = Telegram::I18n.t(key, locale: locale)
        label == key ? value.titleize : label
      end

      def self.coach_mark(game, locale: Telegram::I18n::DEFAULT_LOCALE, with_names: false, channel: :telegram)
        return nil unless game.respond_to?(:with_coach?) && game.with_coach?

        names = with_names ? coach_names(game, locale: locale, channel: channel) : []
        if names.empty?
          Telegram::I18n.t(:coach_with, locale: locale)
        else
          key = names.one? ? :coach_with_name : :coach_with_names
          Telegram::I18n.t(key, locale: locale, names: names.join(", "))
        end
      end

      # Тренера зовут так же, как игрока в списке участников, а отказавшийся
      # тренер на корт не придёт — его имени в напоминании нет.
      def self.coach_names(game, locale: Telegram::I18n::DEFAULT_LOCALE, channel: :telegram)
        return [] unless game.respond_to?(:coaches)

        coaches = game.coaches.reject { |coach| game.invitation_status_for(coach) == "declined" }
        coaches.map do |coach|
          UserLookup.display_name(coach, fallback: Telegram::I18n.t(:user_fallback, locale: locale), channel: channel)
        end
      end

      # План занятия в одну строку: названия блоков без описаний и минут.
      #
      # Режем по целым блокам: «Подачи на т...» посреди слова не читается, а
      # сколько блоков не поместилось — видно из хвоста. Предел нужен, чтобы
      # длинный план не выбил всё сообщение за 4096 символов телеграма.
      def self.training_program(game, limit: 600, locale: Telegram::I18n::DEFAULT_LOCALE)
        return nil unless game.respond_to?(:game_training_blocks)

        titles = game.game_training_blocks.filter_map { |entry| entry.training_block&.title&.strip.presence }
        return nil if titles.empty?

        kept = []
        titles.each do |title|
          break if kept.any? && (kept + [ title ]).join(", ").length > limit
          kept << title
        end

        text = kept.join(", ")
        dropped = titles.size - kept.size
        return text if dropped.zero?

        "#{text} #{Telegram::I18n.t(:program_more, locale: locale, count: dropped)}"
      end

      def self.resolve_date(game)
        if game.respond_to?(:display_date_for_show)
          game.display_date_for_show
        elsif game.respond_to?(:next_date)
          game.next_date
        elsif game.respond_to?(:date)
          game.date
        end
      end

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
