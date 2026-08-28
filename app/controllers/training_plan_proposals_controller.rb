# Правки плана тренировки: предлагает участник, судьбу решает организатор, а
# при голосовании — состав игры.
class TrainingPlanProposalsController < ApplicationController
  before_action :set_game
  before_action :set_proposal, except: :create
  before_action :authorize_team_member!, only: :create
  before_action :authorize_game_manager!, only: %i[update approve reject]

  def create
    @proposal = @game.training_plan_proposals.new(proposal_attributes.merge(user: current_user))

    if @proposal.save
      # Организатору спрашивать разрешения не у кого — его правка идёт сразу.
      can_manage?(@game) ? approve_and_notify : TrainingPlanProposalNotifier.approval_requested(@proposal)
      redirect_to @game, notice: t("games.training_plan_proposals.#{created_notice_key}")
    else
      redirect_to @game, alert: @proposal.errors.full_messages.to_sentence
    end
  end

  # Организатор может поправить предложенное, прежде чем пускать его дальше.
  def update
    return redirect_to @game, alert: t("games.training_plan_proposals.closed") unless @proposal.pending?

    if @proposal.update(proposal_attributes)
      redirect_to @game, notice: t("games.training_plan_proposals.updated")
    else
      redirect_to @game, alert: @proposal.errors.full_messages.to_sentence
    end
  end

  def approve
    return redirect_to @game, alert: t("games.training_plan_proposals.closed") unless @proposal.pending?

    approve_and_notify
    redirect_to @game, notice: t("games.training_plan_proposals.#{@proposal.applied? ? "applied" : "vote_started"}")
  end

  def reject
    return redirect_to @game, alert: t("games.training_plan_proposals.closed") unless @proposal.open?

    @proposal.reject!
    TrainingPlanProposalNotifier.settled(@proposal)
    redirect_to @game, notice: t("games.training_plan_proposals.rejected")
  end

  def vote
    unless @proposal.vote!(current_user, ActiveModel::Type::Boolean.new.cast(params[:in_favor]))
      return redirect_to @game, alert: t("games.training_plan_proposals.vote_not_allowed")
    end

    TrainingPlanProposalNotifier.settled(@proposal) unless @proposal.open?
    redirect_to @game, notice: t("games.training_plan_proposals.vote_counted")
  end

  # Автор забирает правку назад, организатор — убирает лишнее из списка.
  def destroy
    unless @proposal.user_id == current_user.id || can_manage?(@game)
      return head :forbidden
    end

    @proposal.destroy
    redirect_to @game, notice: t("games.training_plan_proposals.removed")
  end

  private

  def set_game
    @game = Game.find(params[:game_id])
  end

  def set_proposal
    @proposal = @game.training_plan_proposals.find(params[:id])
  end

  def authorize_team_member!
    head :forbidden unless team_member?
  end

  def authorize_game_manager!
    head :forbidden unless can_manage?(@game)
  end

  def team_member?
    current_user.admin? || @game.team_member_ids.include?(current_user.id)
  end

  def approve_and_notify
    @proposal.approve!

    if @proposal.voting?
      TrainingPlanProposalNotifier.vote_started(@proposal)
    else
      TrainingPlanProposalNotifier.settled(@proposal)
    end
  end

  def created_notice_key
    return "created" unless can_manage?(@game)

    @proposal.applied? ? "applied" : "vote_started"
  end

  def proposal_attributes
    permitted = params.require(:training_plan_proposal).permit(:comment, :mode, training_block_ids: [])

    permitted.to_h.merge("training_block_ids" => allowed_block_ids(permitted[:training_block_ids]))
  end

  # Блок из чужой библиотеки в план не попадает, даже если его id прислали в форме.
  # Своё предложение — исключение: организатор правит его целиком, не теряя блок,
  # который принёс из личной библиотеки автор правки.
  def allowed_block_ids(ids)
    ids = Array(ids).map(&:to_i).uniq.reject(&:zero?)
    owner_ids = ([ current_user.id, @game.user_id ] + @game.assigned_coach_ids).compact.uniq
    known_ids = @game.training_block_ids + Array(@proposal&.training_block_ids)
    allowed = TrainingBlock.available_for(owner_ids, known_ids).where(id: ids).pluck(:id)

    ids.select { |id| allowed.include?(id) }
  end
end
