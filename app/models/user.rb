class User < ApplicationRecord
  has_many :games
  has_many :participations

  before_validation :normalize_email

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :telegram_username, format: { with: /\A@?[\w\d_]{5,32}\z/, message: "is invalid" }, allow_blank: true
  validates :telegram_chat_id, uniqueness: true, allow_nil: true

  def admin?
    admin == true
  end

  # ensure registration token for bot-based registration
  def ensure_telegram_registration_token!
    return telegram_registration_token if telegram_registration_token.present?

    token = SecureRandom.hex(12)
    update_column(:telegram_registration_token, token)
    token
  end

  def clear_telegram_registration_token!
    update_column(:telegram_registration_token, nil)
  end

 def regenerate_telegram_registration_token!
   loop do
     token = SecureRandom.hex(12)
     # уникальность (индекс уникальный, но лучше не ловить исключение)
     unless self.class.exists?(telegram_registration_token: token)
       update_column(:telegram_registration_token, token)

       return token
     end
   end
 end

  def notify_via_telegram(text)
    return false unless telegram_chat_id.present?
    TelegramNotifier.send_message(telegram_chat_id, text)
  rescue => e
    Rails.logger.warn "Telegram send failed for User##{id}: #{e.message}"
    false
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end
end
