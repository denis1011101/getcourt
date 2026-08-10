class ParticipationsController < ApplicationController
  before_action :set_game, only: [ :create, :create_guest, :destroy, :approve, :reject ]
  before_action :authenticate_user!, only: [ :create_guest, :destroy, :approve, :reject ]

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
        ParticipationNotifier.notify_owner(@game, current_user, action: :requested) rescue nil
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
    GameRequestNotification.participation(user: @participation.user, game: @game, approved: true)

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

  def create_guest
    return head :forbidden unless can_manage_game?

    name = params[:guest_name].to_s.strip[0, 50]
    if name.blank?
      respond_to do |format|
        format.turbo_stream { render plain: "Guest name can't be blank.", status: :unprocessable_entity }
        format.html { redirect_to @game, alert: "Guest name can't be blank." }
      end
      return
    end

    @participation = @game.participations.build(guest_name: name, status: "approved", approved_at: Time.current)

    if @participation.save
      ParticipationNotifier.notify_owner(@game, @participation, action: :guest_added) if current_user != @game.user

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("participations", partial: "participations/list", locals: { game: @game }),
            turbo_stream.replace("participation_controls", partial: "participations/controls", locals: { game: @game })
          ]
        end
        format.html { redirect_to @game, notice: "Guest added." }
      end
    else
      msg = @participation.errors.full_messages.to_sentence.presence || "Failed to add guest."
      respond_to do |format|
        format.turbo_stream { render plain: msg, status: :unprocessable_entity }
        format.html { redirect_to @game, alert: msg }
      end
    end
  end

  def reject
    return head :forbidden unless can_manage_game?

    @participation = @game.participations.find_by(id: params[:id])
    return head :not_found unless @participation

    requester = @participation.user
    @participation.destroy
    GameRequestNotification.participation(user: requester, game: @game, approved: false)

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

    allowed =
      if @participation.guest?
        can_manage_game?
      else
        AccessControl.can_remove_participant?(current_user, @game, @participation.user)
      end

    unless allowed
      head :forbidden and return
    end

    @participation_id = @participation.id
    removed_user = @participation.user
    removed_participation = @participation
    @participation.destroy

    # The owner does not need to be told about a removal they performed themselves.
    if @participation_id && @game.user && current_user != @game.user
      if removed_participation.guest?
        ParticipationNotifier.notify_owner(@game, removed_participation, action: :removed)
      else
        action = (removed_user == current_user) ? :left : :removed
        ParticipationNotifier.notify_owner(@game, removed_user, action: action)
      end
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
