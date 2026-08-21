class TrainingBlock < ApplicationRecord
  # Блок живёт в библиотеке тренера: заполнил один раз — дальше только выбираешь.
  belongs_to :user
  has_many :game_training_blocks, dependent: :destroy
  has_many :games, through: :game_training_blocks

  MAX_DURATION_MINUTES = 600

  before_validation :normalize_title

  validates :title, presence: true, length: { maximum: 100 }
  validates :description, length: { maximum: 500 }, allow_blank: true
  validates :duration_minutes,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_DURATION_MINUTES },
            allow_nil: true
  validate :title_is_free_in_library

  scope :ordered, -> { order(:title) }

  # Повторное добавление блока с тем же названием должно попадать в уже
  # существующий, иначе уникальный индекс уронил бы сохранение игры.
  def self.build_for(user, attributes)
    title = attributes[:title].to_s.strip
    block = named(user, title) || new(user: user, title: title)
    block.description = attributes[:description].to_s.strip.presence
    block.duration_minutes = attributes[:duration_minutes].presence
    block
  end

  # SQLite не умеет приводить кириллицу к нижнему регистру, поэтому названия
  # сравниваем в Ruby: библиотека одного тренера всё равно небольшая.
  def self.named(user, title, except: nil)
    where(user: user).where.not(id: except).detect { |block| block.title.casecmp?(title.to_s.strip) }
  end

  def label
    return title if duration_minutes.blank?

    "#{title} · #{duration_minutes} #{I18n.t("training_blocks.minutes_short")}"
  end

  private

  def normalize_title
    self.title = title.to_s.strip
  end

  def title_is_free_in_library
    return if title.blank?

    errors.add(:title, :taken) if self.class.named(user, title, except: id).present?
  end
end
