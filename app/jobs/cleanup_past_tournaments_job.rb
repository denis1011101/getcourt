class CleanupPastTournamentsJob < ApplicationJob
  queue_as :default

  # Remove tournaments whose end_date (or start_date if end_date is absent) is strictly in the past,
  # along with all dependent records: matches, tournament games, participants, courts, dates.
  def perform
    past_tournaments = Tournament.all.select do |t|
      cutoff = t.end_date.presence || t.start_date
      cutoff.present? && cutoff < Date.current
    end

    past_tournaments.each do |tournament|
      id = tournament.id

      TournamentMatch.where(tournament_id: id).delete_all
      Rails.logger.info "Deleted TournamentMatches for Tournament##{id}"

      game_ids = Game.where(tournament_id: id).pluck(:id)
      if game_ids.any?
        Match.where(game_id: game_ids).update_all(game_id: nil)
        PlayerStatisticEntry.where(game_id: game_ids).update_all(game_id: nil)
        Participation.where(game_id: game_ids).delete_all
        Game.where(id: game_ids).destroy_all
        Rails.logger.info "Deleted #{game_ids.size} Games (and their related records) for Tournament##{id}"
      end

      TournamentParticipant.where(tournament_id: id).delete_all
      TournamentCourt.where(tournament_id: id).delete_all
      TournamentDate.where(tournament_id: id).delete_all

      if tournament.destroy
        Rails.logger.info "Destroyed past Tournament##{id}"
      else
        Rails.logger.warn "Failed to destroy Tournament##{id}: #{tournament.errors.full_messages.join(', ')}"
      end
    end
  end
end
