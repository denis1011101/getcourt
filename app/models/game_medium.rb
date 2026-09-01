# Фото или ролик, приложенный к игре. Таблица называется game_media, поэтому
# рельсовое единственное число — GameMedium.
#
# Хранилище — :local, то есть файлы лежат на диске прода рядом с приложением
# (см. data-disk-runbook.md). Отсюда жёсткие лимиты ниже: без них видео забивает
# раздел за считаные загрузки. Когда появится S3/GCS, лимиты можно ослабить.
class GameMedium < ApplicationRecord
  IMAGE_TYPES = %w[image/jpeg image/png image/webp].freeze
  VIDEO_TYPES = %w[video/mp4 video/quicktime].freeze
  CONTENT_TYPES = (IMAGE_TYPES + VIDEO_TYPES).freeze

  MAX_IMAGE_SIZE = 5.megabytes
  MAX_VIDEO_SIZE = 25.megabytes
  MAX_TITLE_LENGTH = 100
  MAX_IMAGES_PER_GAME = 6
  MAX_VIDEOS_PER_GAME = 1

  belongs_to :game
  belongs_to :user

  has_one_attached :file

  scope :visible, -> { where(hidden_at: nil) }
  # Витрина Tennis Life открыта без логина, поэтому попадание туда — отдельное
  # решение автора, а не следствие загрузки. См. GameMediaController#update.
  scope :in_feed, -> { where(show_in_feed: true) }
  scope :newest_first, -> { order(created_at: :desc) }

  validates :title, length: { maximum: MAX_TITLE_LENGTH }, allow_blank: true
  validate :file_attached
  validate :supported_content_type
  validate :within_size_limit
  validate :within_count_limit, on: :create

  def image?
    IMAGE_TYPES.include?(content_type)
  end

  def video?
    VIDEO_TYPES.include?(content_type)
  end

  def content_type
    file.attached? ? file.blob.content_type : nil
  end

  def hidden?
    hidden_at.present?
  end

  def hide!
    update!(hidden_at: Time.current)
  end

  # Превью для ленты и карточки игры. У видео варианта нет — там показываем
  # сам плеер.
  #
  # Валидация типа проверяет content_type, а его Active Storage берёт из
  # сигнатуры файла и только при неудаче — из заявленного клиентом. То есть
  # мусор, названный image/png, до сюда доедет и развалится уже на обработке
  # варианта. Лента публичная, и одно битое вложение не должно ронять страницу,
  # поэтому здесь nil вместо исключения.
  def preview_variant
    return nil unless image?

    file.variant(resize_to_limit: [ 1200, 630 ]).processed
  rescue StandardError => e
    Rails.logger.warn("[GameMedium##{id}] preview failed: #{e.class}: #{e.message}")
    nil
  end

  private

  def file_attached
    errors.add(:file, :blank) unless file.attached?
  end

  def supported_content_type
    return unless file.attached?
    return if CONTENT_TYPES.include?(content_type)

    errors.add(:file, :invalid_type)
  end

  def within_size_limit
    return unless file.attached?

    limit = video? ? MAX_VIDEO_SIZE : MAX_IMAGE_SIZE
    return if file.blob.byte_size <= limit

    errors.add(:file, :too_large)
  end

  def within_count_limit
    return unless file.attached? && game

    siblings = GameMedium.where(game_id: game_id).includes(file_attachment: :blob).to_a
    if video?
      errors.add(:base, :too_many_videos) if siblings.count(&:video?) >= MAX_VIDEOS_PER_GAME
    else
      errors.add(:base, :too_many_images) if siblings.count(&:image?) >= MAX_IMAGES_PER_GAME
    end
  end
end
