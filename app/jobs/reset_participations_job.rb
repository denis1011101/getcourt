class ResetParticipationsJob < ApplicationJob
  queue_as :default

  def perform
    Game.where(recurring: true).find_each do |game|
      nd = game.next_date
      next unless nd
      if game.should_reset_participations?(Date.today)
        game.participations.delete_all
        game.mark_participations_reset!(nd)
        Rails.logger.info "Reset participations for Game##{game.id} for occurrence #{nd}"
      end
    end
  end
end
