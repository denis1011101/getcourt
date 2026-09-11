module Telegram
  module Chat
    # Письмо тем, кто в чате остался. Рядом, в Closure, живёт письмо выбывшим:
    # там указатель на чат гасят, а здесь состав при чате остаётся — у него
    # просто новое занятие, и человек должен видеть, про какую игру теперь
    # переписка. Со звуком: сброс идёт вечером, и это не то письмо, которое
    # приходит спящему (ночь в чужом часовом поясе доберёт Telegram::QuietHours).
    module Announcement
      class << self
        def notify(game, reason, users = nil)
          return 0 if game.nil?

          (users || game.chat_members).to_a.count do |user|
            next false if user.nil? || user.telegram_chat_id.blank?

            deliver(user, text(game, reason, Telegram::I18n.locale_for(user)))
          end
        end

        private

        def text(game, reason, locale)
          occurrence = game.display_date_for_show || game.date

          Telegram::I18n.t(
            reason,
            locale: locale,
            date: occurrence ? ::I18n.l(occurrence, format: :telegram, locale: locale) : "—",
            time: Telegram::Helpers::GameFormatting.format_time_hhmm(game.time, locale: locale) || "—:--",
            court: game.court&.name.to_s
          )
        end

        # Одна упавшая отправка не должна съесть письма остальных: второго
        # захода по этому составу не будет, сброс уже случился.
        def deliver(user, text)
          SendTelegramNotificationJob.perform_later(user.telegram_chat_id.to_s, text)
          true
        rescue StandardError => e
          Rails.logger.warn("[Chat::Announcement] failed for User##{user.id}: #{e.class}: #{e.message}")
          false
        end
      end
    end
  end
end
