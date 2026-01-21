class ParticipationsController < ApplicationController
  before_action :set_game, only: [:create, :destroy]
  before_action :authenticate_user!, only: [:destroy]

  def create
    unless current_user
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("participation_controls",
            partial: "participations/controls",
            locals: { sign_in_path: new_session_path })
        end
        format.html { redirect_to new_session_path }
      end
      return
    end

    @participation = @game.participations.build(user: current_user)

    if @participation.save
      Telegram::ParticipationNotifier.notify_owner(@game, current_user, action: :joined)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @game, notice: 'Successfully joined the game.' }
      end
    else
      msg = @participation.errors.full_messages.to_sentence.presence || 'Failed to join the game.'
      respond_to do |format|
        format.turbo_stream { render plain: msg, status: :unprocessable_entity }
        format.html { redirect_to @game, alert: msg }
      end
    end
  rescue ActiveRecord::RecordNotUnique
    respond_to do |format|
      format.turbo_stream { head :ok }
      format.html { redirect_to @game, alert: 'You have already joined this game.' }
    end
  end

  def destroy
    @participation = @game.participations.find_by(id: params[:id]) ||
                     @game.participations.find_by(user: current_user)
    unless @participation
      head :not_found and return
    end

    unless AccessControl.can_remove_participant?(current_user, @game, @participation.user)
      head :forbidden and return
    end

    @participation_id = @participation.id
    removed_user = @participation.user
    @participation.destroy

    if @participation_id && @game.user&.telegram_chat_id.present?
      action = (removed_user == current_user) ? :left : :removed
      Telegram::ParticipationNotifier.notify_owner(@game, removed_user, action: action)
    end

    respond_to do |format|
      format.turbo_stream { render :destroy }
      format.html { redirect_to @game, notice: 'Participation removed.' }
    end
  end

  private

  def set_game
    @game = Game.find(params[:game_id])
  end
end
