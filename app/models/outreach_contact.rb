require "net/smtp"

# Список адресов для холодной рассылки о брони кортов через GetCourt.
#
# Отправляем маленькими пачками раз в день (см. OutreachEmailJob): Resend и
# почтовые провайдеры принимающей стороны спокойнее относятся к десятку писем в
# сутки с постоянного адреса, чем к сотне разом.
class OutreachContact < ApplicationRecord
  DAILY_BATCH = 10
  MAX_ATTEMPTS = 3
  # Расширенные коды RFC 3463, которыми сервер говорит именно про адрес, куда мы
  # пишем: ящика нет, он отключён, переехал, переполнен. Только они значат, что
  # виноват контакт. Сам по себе класс ошибки этого не значит: 501 5.1.7 — это
  # претензия к нашему адресу отправителя, 5.7.1 — к политике, и списывать их на
  # клуб нельзя. Всё неопознанное считаем своей бедой, а не его.
  RECIPIENT_REJECTIONS = %w[ 5.1.1 5.1.2 5.1.3 5.1.4 5.1.6 5.1.10 5.2.1 5.2.2 ].freeze
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
    #
    # На общем сбое почты пачка обрывается: остаток адресов освобождаем и даём
    # ошибке уйти наверх, чтобы запуск было видно упавшим, а не тихо пустым.
    def deliver_daily_batch_now(limit: DAILY_BATCH)
      batch = reserve_batch(limit)
      sent = 0

      batch.each_with_index do |contact, index|
        sent += 1 if contact.deliver_now
      rescue StandardError
        release(batch[index..])
        raise
      end

      sent
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

      def release(contacts)
        where(id: contacts.map(&:id)).update_all(reserved_at: nil, updated_at: Time.current)
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
    if recipient_rejected?(e)
      Rails.logger.warn "Outreach to #{email} rejected: #{e.class}: #{e.message}"
      update!(attempts: attempts + 1, last_error: error_text(e), reserved_at: nil)
      false
    else
      Rails.logger.error "Outreach to #{email} failed: #{e.class}: #{e.message}"
      update!(last_error: error_text(e), reserved_at: nil)
      raise
    end
  end

  def unsubscribe
    update!(unsubscribed_at: Time.current)
  end

  private
    def recipient_rejected?(error)
      error.is_a?(Net::SMTPError) && RECIPIENT_REJECTIONS.include?(enhanced_status_code(error))
    end

    # Код вида 5.1.1 из ответа сервера; его может и не быть — тогда мы не знаем,
    # чей адрес не понравился, и трогать счётчик контакта не станем.
    def enhanced_status_code(error)
      error.message.to_s[/\b5\.\d{1,3}\.\d{1,3}\b/]
    end

    def error_text(error)
      "#{error.class}: #{error.message}".truncate(255)
    end
end
