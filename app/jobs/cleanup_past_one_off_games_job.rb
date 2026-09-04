class CleanupPastOneOffGamesJob < ApplicationJob
  queue_as :default

  # TODO: Последить удаляются ли нерегулярные прошедшие игры
  #
  # Remove participations for non-recurring games that are strictly in the past,
  # then destroy the one-off game record.
  def perform
    Game.where(recurring: false).where("date < ?", Date.current).find_each do |game|
      # Чат уходит вместе с игрой, а текст письма ссылается на её город и дату —
      # поэтому готовим его до удаления, а шлём только если удаление удалось.
      notices = Telegram::Chat::Closure.prepare(game, :chat_closed_finished)

      if game.participations.exists?
        game.participations.delete_all
        Rails.logger.info "Cleared participations for past one-off Game##{game.id} (date=#{game.date})"
      end

      if game.destroy
        Telegram::Chat::Closure.deliver(game, notices)
        Rails.logger.info "Destroyed past one-off Game##{game.id} (date=#{game.date})"
      else
        Rails.logger.warn "Failed to destroy past one-off Game##{game.id}: #{game.errors.full_messages.join(', ')}"
      end
    end
  end
end
