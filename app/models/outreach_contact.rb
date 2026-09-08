# Список адресов для холодной рассылки о брони кортов через GetCourt.
#
# Отправляем маленькими пачками раз в день (см. OutreachEmailJob): Resend и
# почтовые провайдеры принимающей стороны спокойнее относятся к десятку писем в
# сутки с постоянного адреса, чем к сотне разом.
class OutreachContact < ApplicationRecord
  DAILY_BATCH = 10
  MAX_ATTEMPTS = 3
  # Столько ждём отправки зарезервированного адреса: если процесс упал между
  # резервом и письмом, через час контакт возвращается в очередь.
  RESERVATION_TTL = 1.hour

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # Адрес, на который упало MAX_ATTEMPTS раз, выпадает из очереди: иначе битая
  # строчка занимает место в пачке каждый день до скончания века.
  scope :pending, -> {
    where(sent_at: nil, unsubscribed_at: nil)
      .where(attempts: ...MAX_ATTEMPTS)
      .where("reserved_at IS NULL OR reserved_at < ?", RESERVATION_TTL.ago)
      .order(:id)
  }

  # Что уже съело дневной лимит: письма, ушедшие сегодня, плюс живые резервы —
  # по ним письмо вот-вот уйдёт, и календарная дата резерва тут ни при чём
  # (пачка, взятая в 23:59, рассылается уже «сегодня»). Протухший резерв не в
  # счёт: контакт по нему вернулся в очередь, письма не было.
  scope :daily_limit_taken, -> {
    where(sent_at: Time.current.all_day)
      .or(where(sent_at: nil).where(reserved_at: RESERVATION_TTL.ago..))
  }

  class << self
    def deliver_daily_batch_later(limit: DAILY_BATCH)
      OutreachEmailJob.perform_later(limit)
    end

    # Возвращает число ушедших писем. Больше DAILY_BATCH в сутки не отправит,
    # сколько бы раз за день её ни позвали и что бы ни просили в limit.
    def deliver_daily_batch_now(limit: DAILY_BATCH)
      reserve_batch(limit).count(&:deliver_now)
    end

    # Принимает строки вида `mail@example.com` или `mail@example.com,Клуб`.
    # Возвращает число добавленных контактов, повторы молча пропускает.
    def import(lines)
      lines.sum do |line|
        email, name = line.to_s.strip.split(",", 2)
        next 0 if email.blank? || exists?(email: email.strip.downcase)

        create(email: email, name: name&.strip).persisted? ? 1 : 0
      end
    end

    private
      # Выбор и резерв идут одной транзакцией: адаптер SQLite открывает её как
      # BEGIN IMMEDIATE и сразу берёт write-lock, поэтому ручной запуск и
      # плановый не увидят один и тот же остаток дня и не заберут одни и те же
      # адреса — второй подождёт первого и получит уже пустую очередь.
      def reserve_batch(limit)
        transaction do
          ids = pending.limit(room_left_today(limit)).pluck(:id)
          where(id: ids).update_all(reserved_at: Time.current, updated_at: Time.current)
          # Перечитываем уже с проставленным резервом: без этого объекты в памяти
          # считают reserved_at пустым и не сбросят его после неудачной отправки.
          where(id: ids).order(:id).to_a
        end
      end

      def room_left_today(limit)
        [ limit.to_i, DAILY_BATCH - daily_limit_taken.count ].min.clamp(0, DAILY_BATCH)
      end
  end

  # Зовём только для контактов, зарезервированных `reserve_batch`, — резерв и
  # есть право на отправку.
  def deliver_now
    OutreachMailer.court_booking_pitch(self).deliver_now
    update!(sent_at: Time.current, attempts: attempts + 1, last_error: nil)
    true
  rescue StandardError => e
    Rails.logger.warn "Outreach to #{email} failed: #{e.class}: #{e.message}"
    update!(attempts: attempts + 1, last_error: "#{e.class}: #{e.message}".truncate(255), reserved_at: nil)
    false
  end

  def unsubscribe
    update!(unsubscribed_at: Time.current)
  end
end
