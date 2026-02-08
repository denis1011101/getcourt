class ParticipationsController < ApplicationController
  before_action :set_game, only: [ :create, :destroy, :approve, :reject ]
  before_action :authenticate_user!, only: [ :destroy, :approve, :reject ]

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

    existing = @game.participations.find_by(user: current_user)
    if existing
      msg = existing.respond_to?(:pending?) && existing.pending? ? "Join request already sent." : "You have already joined this game."
      respond_to do |format|
        format.turbo_stream { render plain: msg, status: :unprocessable_entity }
        format.html { redirect_to @game, alert: msg }
      end
      return
    end

    status = (current_user == @game.user || (current_user.respond_to?(:admin?) && current_user.admin?)) ? "approved" : "pending"
    @participation = @game.participations.build(user: current_user, status: status)
    @participation.approved_at = Time.current if status == "approved"

    if @participation.save
      if @participation.pending?
        Telegram::ParticipationNotifier.notify_owner(@game, current_user, action: :requested) rescue nil
      end
      respond_to do |format|
        format.turbo_stream
        if status == "approved"
          format.html { redirect_to @game, notice: "You joined the game." }
        else
          format.html { redirect_to @game, notice: "Join request sent. Waiting for approval." }
        end
      end
    else
      msg = @participation.errors.full_messages.to_sentence.presence || "Failed to join the game."
      respond_to do |format|
        format.turbo_stream { render plain: msg, status: :unprocessable_entity }
        format.html { redirect_to @game, alert: msg }
      end
    end
  rescue ActiveRecord::RecordNotUnique
    respond_to do |format|
      format.turbo_stream { head :ok }
      format.html { redirect_to @game, alert: "You have already joined this game." }
    end
  end

  def approve
    return head :forbidden unless can_manage_game?

    @participation = @game.participations.find_by(id: params[:id])
    return head :not_found unless @participation

    @participation.update(status: "approved", approved_at: Time.current)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("participations", partial: "participations/list", locals: { game: @game }),
          turbo_stream.replace("participation_controls", partial: "participations/controls", locals: { game: @game })
        ]
      end
      format.html { redirect_to @game, notice: "Participant approved." }
    end
  end

  def reject
    return head :forbidden unless can_manage_game?

    @participation = @game.participations.find_by(id: params[:id])
    return head :not_found unless @participation

    @participation.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("participations", partial: "participations/list", locals: { game: @game }),
          turbo_stream.replace("participation_controls", partial: "participations/controls", locals: { game: @game })
        ]
      end
      format.html { redirect_to @game, notice: "Participation rejected." }
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
      format.html { redirect_to @game, notice: "Participation removed." }
    end
  end

  private

  def set_game
    @game = Game.find(params[:game_id])
  end

  def can_manage_game?
    current_user && (current_user == @game.user || (current_user.respond_to?(:admin?) && current_user.admin?))
  end
end
