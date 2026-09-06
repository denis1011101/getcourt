# Личный токен к MCP-серверу: человек выпускает его себе сам в разделе
# безопасности, а не просит у нас почтой.
class ApiToken < ApplicationRecord
  # Срок скользящий, потому что токен лежит в конфиге MCP-клиента, где нет
  # никакого механизма обновления: при жёстком сроке рабочая интеграция однажды
  # молча отвалится с 401, которого живой человек не увидит. Отсчёт от
  # последнего запроса даёт то, ради чего срок и заводили: брошенный токен
  # умирает сам, а тот, которым пользуются, живёт.
  LIFETIME = 6.months
  # Продлеваем не чаще раза в сутки: иначе каждый вызов инструмента — это ещё и
  # запись в базу, а точность «когда пользовались» до дня нас устраивает.
  REFRESH_AFTER = 1.day

  belongs_to :user

  scope :active, -> { where(revoked_at: nil).where(expires_at: Time.current..) }

  class << self
    # Токен на человека один: он настраивает своего ассистента, а не парк машин.
    # Новый выпуск гасит прежний — иначе отозвать доступ станет некуда.
    def issue_for(user)
      transaction do
        active.where(user: user).find_each(&:revoke!)
        create!(user: user, token: generate_token, expires_at: LIFETIME.from_now)
      end
    end

    def authenticate(raw)
      return nil if raw.blank?

      token = active.find_by(token: raw)
      token&.refresh_use!
      token
    end

    private

    def generate_token
      loop do
        token = SecureRandom.hex(32)
        break token unless exists?(token: token)
      end
    end
  end

  def refresh_use!
    return if last_used_at.present? && last_used_at > REFRESH_AFTER.ago

    update_columns(last_used_at: Time.current, expires_at: LIFETIME.from_now)
  end

  def revoke!
    update_columns(revoked_at: Time.current)
  end

  def active?
    revoked_at.nil? && expires_at.future?
  end
end
