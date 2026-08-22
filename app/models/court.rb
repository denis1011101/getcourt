class Court < ApplicationRecord
  serialize :surfaces, coder: JSON, type: Array

  has_many :games, dependent: :destroy
  has_many :favorite_court_links, class_name: "FavoriteCourt", dependent: :destroy
  has_many :court_suggestions, dependent: :destroy
  has_many :fans, through: :favorite_court_links, source: :user
  validates :name, presence: true
  belongs_to :user, optional: true

  SURFACES = %w[hard clay grass artificial_grass].freeze

  before_validation :normalize_surfaces
  validate :surfaces_are_valid

  # планируем асинхронное получение адреса при смене координат
  after_commit :enqueue_address_fetch, on: %i[create update], if: -> { saved_change_to_coordinates? }

  MODERATION_STATUSES = %w[pending approved rejected].freeze
  validates :moderation_status, inclusion: { in: MODERATION_STATUSES }
  CONTACT_TYPES = %w[phone whatsapp telegram viber website email other].freeze
  SPORTS = SportCatalog::SPORTS

  validates :sport, inclusion: { in: SPORTS }, allow_blank: true

  scope :approved, -> { where(moderation_status: "approved") }
  scope :visible_to, ->(user) { user&.admin? ? all : approved }
  scope :free_only, -> { where(free: true) }
  scope :outdoor_only, -> { where(outdoor: true) }
  scope :indoor_only, -> { where(indoor: true) }

  def self.sorted_for_user(user)
    # По id корты идут вперемешку, поэтому раскладываем их по городу и названию.
    courts = all.to_a.sort_by { |court| [ court.city_name.to_s, court.name.to_s ] }
    user_city = user&.city_name.to_s.strip.downcase.presence
    return courts unless user_city

    local, other = courts.partition do |court|
      court.city_name.to_s.strip.downcase == user_city
    end
    local + other
  end

  def surface_labels
    surfaces.map { |key| I18n.t("courts.surfaces.#{key}", default: key.to_s.tr("_", " ").capitalize) }
  end

  # Список сред (indoor/outdoor), доступных на корте — для выбора при создании игры
  def environments
    %w[indoor outdoor].select { |env| public_send("#{env}?") }
  end

  def approved?
    moderation_status == "approved"
  end

  def pending?
    moderation_status == "pending"
  end

  def contact_label
    contact_type.present? ? contact_type.capitalize : nil
  end

  def formatted_contact
    return nil if contact_value.blank?

    contact_links.map { |item| item[:formatted] }.join(", ").presence || (contact_label ? "#{contact_label}: #{contact_value}" : contact_value)
  end

  def contact_links
    contact_entries.filter_map do |value|
      build_contact_link(value)
    end
  end

  def contact_entries_for_form(count = 3)
    entries = contact_entries.map do |value|
      type, normalized_value = extract_contact_type_and_value(value)
      { "contact_type" => type, "contact_value" => normalized_value }
    end

    entries << { "contact_type" => nil, "contact_value" => nil } while entries.size < count
    entries.first(count)
  end

  def self.near(location, radius_km = 10)
    loc = parse_pair(location)
    return none unless loc
    lat, lon = loc

    all.select do |court|
      cloc = court.coordinates_pair
      next false unless cloc
      clat, clon = cloc
      Geocoding::AddressResolver.haversine_km(lat, lon, clat, clon) <= radius_km
    end
  end

  def self.parse_location(str)
    str = str.to_s.strip
    return nil if str.empty?

    if str.match?(/\A-?\d+(\.\d+)?,\s*-?\d+(\.\d+)?\z/)
      parts = str.split(",").map { |s| (Float(s.strip) rescue nil) }
      return nil if parts.any?(&:nil?)
      return parts
    end

    Geocoding::AddressResolver.geocode_text(str)
  end

  def self.haversine_km(lat1, lon1, lat2, lon2)
    rad = Math::PI / 180
    dlat = (lat2 - lat1) * rad
    dlon = (lon2 - lon1) * rad
    a = Math.sin(dlat / 2)**2 + Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dlon / 2)**2
    6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  end

  def address
    return @address if defined?(@address) && @address

    lat, lng = coordinates_pair
    return "Unknown address" unless lat && lng
    return "Unknown address" if lat.zero? && lng.zero?

    cache_key = "addr:#{lat},#{lng}"
    cached = Rails.cache.read(cache_key)
    if cached.present?
      @address = cached
    else
      # не делаем блокирующих сетевых вызовов в рендере — планируем background job
      enqueue_address_fetch
      @address = "Unknown address"
    end
  rescue => e
    Rails.logger.warn("Geocoding failed: #{e.class} #{e.message}")
    @address = "Geocoding error"
  end

  def coordinates_pair
    self.class.parse_pair(coordinates)
  end

  private

  def normalize_surfaces
    self.surfaces = Array(surfaces).map { |s| s.to_s.strip }.reject(&:blank?).uniq
  end

  def surfaces_are_valid
    invalid = surfaces - SURFACES
    errors.add(:surfaces, "contains invalid values: #{invalid.join(', ')}") if invalid.any?
  end

  def contact_entries
    contact_value.to_s.split(/[\n;|]+/).map(&:strip).reject(&:blank?)
  end

  def build_contact_link(value)
    normalized_type, normalized_value = extract_contact_type_and_value(value)
    return nil if normalized_value.blank?

    digits = normalized_value.gsub(/[^\d]/, "")
    href =
      case normalized_type
      when "phone"
        digits.present? ? "tel:+#{digits}" : nil
      when "email"
        "mailto:#{normalized_value}"
      when "website"
        if normalized_value.match?(/\Ahttps?:\/\//)
          normalized_value
        else
          "https://#{normalized_value}"
        end
      when "telegram"
        if normalized_value.match?(/\Ahttps?:\/\//)
          normalized_value
        else
          username = normalized_value.lstrip("@")
          username.present? ? "https://t.me/#{username}" : nil
        end
      when "whatsapp"
        digits.present? ? "https://wa.me/#{digits}" : nil
      when "viber"
        digits.present? ? "viber://chat?number=+#{digits}" : nil
      else
        nil
      end

    label = normalized_type.present? ? normalized_type.capitalize : contact_label
    formatted = [ label, normalized_value ].compact.join(": ")

    { type: normalized_type, value: normalized_value, href: href, label: label, formatted: formatted }
  end

  def extract_contact_type_and_value(value)
    raw = value.to_s.strip
    explicit_type, explicit_value = raw.split(":", 2).map { |part| part.to_s.strip }

    if CONTACT_TYPES.include?(explicit_type)
      return [ normalize_contact_type_value(explicit_type), explicit_value ]
    end

    [ infer_contact_type(raw), raw ]
  end

  def infer_contact_type(value)
    return "email" if value.match?(URI::MailTo::EMAIL_REGEXP)
    return "telegram" if value.match?(/\A@[\w]+\z/) || value.match?(/\Ahttps?:\/\/t\.me\//i)
    return "whatsapp" if value.match?(/\Ahttps?:\/\/wa\.me\//i)
    return "website" if value.match?(/\Ahttps?:\/\//i) || value.match?(/\Awww\./i) || value.match?(/\A[a-z0-9.-]+\.[a-z]{2,}(\/.*)?\z/i)
    return "phone" if value.gsub(/[^\d]/, "").length >= 6

    normalize_contact_type_value(contact_type)
  end

  def normalize_contact_type_value(value)
    case value.to_s
    when "site"
      "website"
    when "mail"
      "email"
    else
      value.to_s
    end
  end

  def enqueue_address_fetch
    Geocoding::FetchCourtAddressJob.perform_later(id)
  end

  def self.parse_pair(str)
    parts = str.to_s.split(",").map { |s| (Float(s) rescue nil) }
    return nil if parts.length < 2 || parts.any?(&:nil?)
    [ parts[0], parts[1] ]
  end
end
