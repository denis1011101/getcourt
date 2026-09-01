# Один внешний пост: сеть + тип + ключ материала. Ключ вместо game_id, потому что
# welcome и daily к играм не привязаны вовсе, а плодить по колонке на каждую новую
# сеть в games не хочется.
class SocialPost < ApplicationRecord
  KINDS = %w[welcome urgent daily].freeze

  validates :network, presence: true
  validates :dedup_key, presence: true
  validates :kind, inclusion: { in: KINDS }

  scope :for_kind, ->(kind) { where(kind: kind) }
end
