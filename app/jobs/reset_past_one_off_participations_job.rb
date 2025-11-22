class ResetPastOneOffParticipationsJob < ApplicationJob
  queue_as :default

  # Remove participations for non-recurring games that are strictly in the past
  def perform
    Game.where(recurring: false).where("date < ?", Date.current).find_each do |game|
      next if game.participations.empty?

      game.participations.delete_all
      Rails.logger.info "Cleared participations for past one-off Game##{game.id} (date=#{game.date})"
    end
  end
end
