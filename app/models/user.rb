class User < ApplicationRecord
  before_validation :normalize_email, :titleize_city_name
  before_validation :set_default_registration_source, on: :create

  has_one :player_statistic, dependent: :destroy
  after_create :ensure_player_statistic

  SKILL_LEVELS = %w[beginner intermediate advanced pro].freeze
  SPORTS = [ "Tennis", "Padel", "Squash", "Table Tennis" ].freeze

  TIMEZONES = (
    TZInfo::Timezone.all_identifiers + ActiveSupport::TimeZone.all.map(&:name)
  ).uniq.freeze

  # generate one-time login code and remember send time/method
  def generate_login_code!(via: "email")
    # 4-digit numeric one-time code (uniform 0000..9999)
    code = format("%04d", SecureRandom.random_number(10_000))
    update_columns(login_code: code, login_code_sent_at: Time.current, login_via: via.to_s)
    code
  end

  # valid only for X minutes
  def valid_login_code?(code, ttl_minutes: 15)
    return false if login_code.blank? || login_code_sent_at.blank?
    return false if Time.current > (login_code_sent_at + ttl_minutes.minutes)
    ActiveSupport::SecurityUtils.secure_compare(login_code.to_s, code.to_s)
  end

  def clear_login_code!
    update_columns(login_code: nil, login_code_sent_at: nil, login_via: nil)
  end

  # store preferred_sports as JSON array in a text column, default empty array
  attribute :preferred_sports, :json, default: []
  attribute :skill_levels, :json, default: {}
  attribute :timezone, :string
  attribute :telegram_locale, :string, default: "ru"

  TELEGRAM_LOCALES = %w[ru en].freeze
  validates :telegram_locale, inclusion: { in: TELEGRAM_LOCALES }, allow_blank: true

  # возвращает уровень для спорта (строка или nil)
  def skill_level_for(sport)
    skill_levels.to_h[sport]
  end

  def set_skill_level_for(sport, level)
    s = skill_levels.to_h
    if level.present?
      s[sport] = level
    else
      s.delete(sport)
    end
    update_column(:skill_levels, s)
  end

  def skill_level_display_for(sport)
    skill_level_for(sport)&.titleize
  end

  # валидации (опционально)
  validate :skill_levels_values_valid

  has_many :games
  has_many :participations

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :telegram_username, format: { with: /\A@?[\w\d_]{5,32}\z/, message: "is invalid" }, allow_blank: true
  validates :telegram_chat_id, uniqueness: true, allow_nil: true
  validates :skill_level, inclusion: { in: SKILL_LEVELS }, allow_nil: true
  validates :timezone, inclusion: { in: TIMEZONES }, allow_blank: true

  # return stored timezone or default (Yekaterinburg)
  def timezone_or_default
    read_attribute(:timezone).presence || "Asia/Yekaterinburg"
  end

  def admin?
    admin == true
  end

  def skill_level_display
    skill_level&.titleize
  end

  def coach?
    self.coach == true
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

  def ensure_player_statistic
    create_player_statistic unless player_statistic
  end

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
    true  # явно возвращаем true
  end

  def titleize_city_name
    self.city_name = city_name.to_s.titleize.presence
    true  # <-- FIX: явно возвращаем true, чтобы не прерывать save
  end

  def set_default_registration_source
    self.registration_source = "email" if registration_source.blank?
    true  # явно возвращаем true
  end

  def skill_levels_values_valid
    return if skill_levels.blank?
    unless skill_levels.is_a?(Hash)
      errors.add(:skill_levels, "must be a hash")
      return
    end

    skill_levels.each do |sport, level|
      next if level.blank?
      unless SPORTS.include?(sport) && SKILL_LEVELS.include?(level)
        errors.add(:skill_levels, "contains invalid entry for #{sport}")
      end
    end
  end
end
