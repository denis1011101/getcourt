class TournamentParticipantsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_tournament
  before_action :authorize_organizer!

  # approve a pending join request
  def update
    participant.approve!
    redirect_back fallback_location: tournament_path(@tournament), notice: t("tournaments.flash.participant_approved")
  end

  # reject a join request or remove a participant
  def destroy
    participant.destroy
    redirect_back fallback_location: tournament_path(@tournament), notice: t("tournaments.flash.participant_removed")
  end

  private
    def set_tournament
      @tournament = Tournament.find(params[:tournament_id])
    end

    def authorize_organizer!
      unless @tournament.organizer?(current_user)
        redirect_back fallback_location: tournament_path(@tournament), alert: t("tournaments.flash.not_authorized")
      end
    end

    def participant
      @participant ||= @tournament.tournament_participants.find(params[:id])
    end
end
