class TrainingBlock < ApplicationRecord
  # Блок живёт в библиотеке тренера: заполнил один раз — дальше только выбираешь.
  belongs_to :user
  has_many :game_training_blocks, dependent: :destroy
  has_many :games, through: :game_training_blocks

  MAX_DURATION_MINUTES = 600

  # Видео к упражнению — ссылка на популярный хостинг, а не что угодно:
  # чужую ссылку показывают всем участникам тренировки, и вести она должна
  # туда, где ролик, а не на произвольный сайт. Ключ — хост без «www»,
  # поддомены (m.youtube.com, vm.tiktok.com) считаются тем же хостером.
  VIDEO_HOSTS = {
    "youtube.com" => "YouTube",
    "youtu.be" => "YouTube",
    "youtube-nocookie.com" => "YouTube",
    "vimeo.com" => "Vimeo",
    "tiktok.com" => "TikTok",
    "instagram.com" => "Instagram",
    "twitch.tv" => "Twitch",
    "dailymotion.com" => "Dailymotion"
  }.freeze

  before_validation :normalize_title
  before_validation :normalize_video_url

  validates :title, presence: true, length: { maximum: 100 }
  validates :description, length: { maximum: 500 }, allow_blank: true
  validates :duration_minutes,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_DURATION_MINUTES },
            allow_nil: true
  validate :title_is_free_in_library
  validate :video_url_points_to_a_video_host

  scope :ordered, -> { order(:title) }
  # Общие блоки GetCourt доступны любому организатору — и когда тренер выбран,
  # и когда его ещё не выбрали. extra_ids держит в списке блоки уже собранного
  # плана: тренер мог убрать блок из общих уже после того, как игру составили.
  scope :available_for, ->(owner_ids, extra_ids = []) {
    where(user_id: owner_ids).or(where(shared: true)).or(where(id: extra_ids))
  }

  # Повторное добавление блока с тем же названием должно попадать в уже
  # существующий, иначе уникальный индекс уронил бы сохранение игры.
  def self.build_for(user, attributes)
    title = attributes[:title].to_s.strip
    block = named(user, title) || new(user: user, title: title)
    block.description = attributes[:description].to_s.strip.presence
    block.duration_minutes = attributes[:duration_minutes].presence
    block.video_url = attributes[:video_url].to_s.strip.presence
    # Снять блок с общих можно только в библиотеке: галка в форме игры о чужих
    # планах ничего не знает.
    block.shared = true if ActiveModel::Type::Boolean.new.cast(attributes[:shared])
    block
  end

  # SQLite не умеет приводить кириллицу к нижнему регистру, поэтому названия
  # сравниваем в Ruby: библиотека одного тренера всё равно небольшая.
  def self.named(user, title, except: nil)
    where(user: user).where.not(id: except).detect { |block| block.title.casecmp?(title.to_s.strip) }
  end

  # Схему присылают JSON-строкой из скрытого поля формы, поэтому нормализуем её
  # в сеттере: в базе всегда лежит уже проверенная структура.
  def diagram=(value)
    super(Diagram.normalize(value))
  end

  def diagram_frames
    Diagram.frames(diagram)
  end

  def diagram?
    Diagram.any?(diagram)
  end

  def label
    return title if duration_minutes.blank?

    "#{title} · #{duration_minutes} #{I18n.t("training_blocks.minutes_short")}"
  end

  def video?
    video_url.present?
  end

  # Название хостера для подписи ссылки: «YouTube», а не голый адрес.
  def video_host
    self.class.video_host_for(video_url)
  end

  def self.video_host_for(url)
    host = (URI.parse(url.to_s).host rescue nil).to_s.downcase.delete_prefix("www.")
    return nil if host.blank?

    _, label = VIDEO_HOSTS.find { |known, _| host == known || host.end_with?(".#{known}") }
    label
  end

  private

  def normalize_title
    self.title = title.to_s.strip
  end

  # Адрес чаще вставляют без схемы — «youtube.com/watch?v=…» — и это не повод
  # отказывать; пустую строку превращаем в nil, чтобы не хранить её.
  def normalize_video_url
    url = video_url.to_s.strip
    url = "https://#{url}" if url.present? && !url.match?(%r{\Ahttps?://}i)
    self.video_url = url.presence
  end

  def video_url_points_to_a_video_host
    return if video_url.blank?

    uri = URI.parse(video_url) rescue nil
    valid = uri.is_a?(URI::HTTP) && self.class.video_host_for(video_url).present?
    errors.add(:video_url, I18n.t("training_blocks.video_url_unsupported")) unless valid
  end

  def title_is_free_in_library
    return if title.blank?

    errors.add(:title, :taken) if self.class.named(user, title, except: id).present?
  end
end
