class User < ApplicationRecord
  before_validation :normalize_email, :titleize_city_name, :set_default_notification_channel
  before_validation :set_default_registration_source, on: :create

  has_one :player_statistic, dependent: :destroy
  belongs_to :merged_into, class_name: "User", optional: true
  has_many :merged_users, class_name: "User", foreign_key: :merged_into_id, dependent: :nullify, inverse_of: :merged_into
  after_create :ensure_player_statistic

  # Accounts merged into another one stay in the table for history, but must not
  # show up anywhere people are listed or picked.
  scope :not_merged, -> { where(merged_at: nil) }

  # People we can offer in a picker: those with a name, plus those who came from
  # the bot and have only a @nick.
  scope :identifiable, -> { where.not(name: [ nil, "" ]).or(where.not(telegram_username: [ nil, "" ])) }

  # Ordered by the label the picker shows (see ApplicationHelper#user_display_label),
  # so the list reads in the order it looks.
  scope :by_display_label, -> {
    order(Arel.sql("LOWER(COALESCE(NULLIF(users.name, ''), users.telegram_username, users.email))"))
  }

  SKILL_LEVELS = %w[beginner intermediate advanced pro].freeze
  SPORTS = SportCatalog::SPORTS

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
  attribute :telegram_locale, :string
  attribute :recent_invite_handles, :json, default: []

  RECENT_INVITE_LISTS_LIMIT = 5

  TELEGRAM_LOCALES = %w[ru en es].freeze
  WEB_LOCALES = %w[en es ru].freeze
  NOTIFICATION_CHANNELS = %w[email telegram].freeze

  validates :telegram_locale, inclusion: { in: TELEGRAM_LOCALES }, allow_blank: true
  validates :locale, inclusion: { in: WEB_LOCALES }, allow_blank: true
  validates :notification_channel, inclusion: { in: NOTIFICATION_CHANNELS }

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
  has_many :coached_games, class_name: "Game", foreign_key: :coach_id, dependent: :nullify, inverse_of: :coach
  has_many :coach_prebookings, foreign_key: :coach_id, dependent: :destroy, inverse_of: :coach
  has_many :participations
  has_many :favorite_court_links, class_name: "FavoriteCourt", dependent: :destroy
  has_many :court_suggestions, dependent: :destroy
  has_many :reviewed_court_suggestions, class_name: "CourtSuggestion", foreign_key: :reviewed_by_id, dependent: :nullify, inverse_of: :reviewed_by
  has_many :favorite_courts, through: :favorite_court_links, source: :court

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

  # The newcomer checklist on the homepage: kept server-side on purpose, so closing
  # it on a laptop doesn't bring it back on a phone.
  def onboarding_dismissed?
    onboarding_dismissed_at.present?
  end

  def dismiss_onboarding!
    update_column(:onboarding_dismissed_at, Time.current)
  end

  # keep the latest invite lists handy, so the same group can be invited again in one click
  def remember_invite_handles(handles)
    handles = handles.map(&:to_s).uniq
    return if handles.empty?

    others = recent_invite_handles.to_a.reject { |list| list.sort == handles.sort }
    update_column(:recent_invite_handles, [ handles ] + others.first(RECENT_INVITE_LISTS_LIMIT - 1))
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

  def set_default_notification_channel
    self.notification_channel ||= telegram_chat_id.present? ? "telegram" : "email"
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
