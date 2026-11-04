class ReportsController < ApplicationController
  skip_before_action :authenticate_user!
  rate_limit to: 15, within: 1.minute, only: :create

  ALLOWED_TARGET_TYPES = %w[GameMedium TrainingBlock TrainingPlanProposal User].freeze

  def create
    target_type = params[:target_type].to_s
    unless ALLOWED_TARGET_TYPES.include?(target_type)
      return render json: { error: "Invalid target type" }, status: :unprocessable_entity
    end

    record = find_target_record(target_type, params[:target_id])
    unless record
      return render json: { error: "Target not found" }, status: :not_found
    end

    author = target_author_label(record)
    reporter = current_user ? (current_user.name.presence || current_user.email) : "Guest (#{request.remote_ip})"
    target_url = target_record_url(record)
    reason = params[:reason].to_s.strip.presence || t("ugc.reasons.inappropriate")

    delivered = Telegram::AdminNotifier.notify_ugc_report(
      target_type: target_type,
      target_id: record.id,
      author: author,
      reporter: reporter,
      reason: reason.truncate(200),
      url: target_url
    )

    if delivered
      respond_to do |format|
        format.json { render json: { ok: true, message: t("ugc.report_success") } }
        format.html { redirect_back fallback_location: root_path, notice: t("ugc.report_success") }
      end
    else
      respond_to do |format|
        format.json { render json: { ok: false, error: t("ugc.report_failed") }, status: :service_unavailable }
        format.html { redirect_back fallback_location: root_path, alert: t("ugc.report_failed") }
      end
    end
  end

  private

  def find_target_record(target_type, target_id)
    case target_type
    when "GameMedium"
      GameMedium.visible.find_by(id: target_id)
    when "TrainingBlock"
      block = TrainingBlock.find_by(id: target_id)
      block if block && training_block_visible?(block)
    when "TrainingPlanProposal"
      TrainingPlanProposal.joins(:game).find_by(id: target_id)
    when "User"
      User.find_by(id: target_id)
    end
  end

  def training_block_visible?(block)
    return true if block.shared?
    return true if current_user && block.user_id == current_user.id
    return true if block.game_training_blocks.exists?

    TrainingPlanProposal.where(
      "EXISTS (SELECT 1 FROM json_each(training_plan_proposals.training_block_ids) WHERE value = ?)",
      block.id
    ).exists?
  end

  def target_author_label(record)
    user = record.is_a?(User) ? record : record.try(:user)
    user&.name.presence || user&.email.presence || "Anonymous"
  end

  def target_record_url(record)
    case record
    when GameMedium, TrainingPlanProposal
      game_url(record.game_id) if record.game_id
    when TrainingBlock
      game = record.games.first
      game ? game_url(game) : root_url
    when User
      user_url(record)
    else
      root_url
    end
  rescue StandardError
    root_url
  end
end
