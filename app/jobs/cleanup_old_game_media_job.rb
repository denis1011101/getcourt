# Убирает фото и ролики, которым больше месяца.
#
# Хранилище локальное (см. GameMedium), поэтому место надо освобождать самим:
# скрытые модерацией вложения файл с диска не снимают, а игры сами по себе не
# удаляются. Ходим по одной записи и зовём destroy, а не delete_all, — только
# так Active Storage снимет вложение и удалит файл.
class CleanupOldGameMediaJob < ApplicationJob
  queue_as :default

  RETENTION = 1.month

  def perform(retention: RETENTION)
    cutoff = retention.ago
    scope = GameMedium.where(created_at: ...cutoff)
    total = scope.count
    return if total.zero?

    destroyed = 0
    scope.find_each do |medium|
      if medium.destroy
        destroyed += 1
      else
        Rails.logger.warn "Failed to destroy GameMedium##{medium.id}: #{medium.errors.full_messages.join(', ')}"
      end
    end

    Rails.logger.info "Destroyed #{destroyed}/#{total} GameMedia older than #{cutoff}"
  end
end
