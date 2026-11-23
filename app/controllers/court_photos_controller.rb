class CourtPhotosController < ApplicationController
  before_action :authenticate_user!
  before_action :set_court
  before_action :set_photo, only: %i[destroy approve reject]

  def create
    @photo = @court.court_photos.build(user: current_user)
    @photo.file.attach(photo_params[:file]) if photo_params[:file].present?

    if current_user.admin?
      @photo.status = "approved"
      @photo.reviewed_by = current_user
      @photo.reviewed_at = Time.current
    else
      @photo.status = "pending"
    end

    if @photo.save
      if @photo.pending?
        Telegram::AdminNotifier.notify_court_photo(@photo, base_url: request.base_url)
        redirect_to @court, notice: t("courts.photos.pending_notice")
      else
        redirect_to @court, notice: t("courts.photos.approved_notice")
      end
    else
      redirect_to @court, alert: @photo.errors.full_messages.to_sentence
    end
  end

  def approve
    return head :forbidden unless current_user&.admin?

    if @photo.approve_by!(current_user)
      redirect_to @court, notice: t("courts.photos.approved_notice")
    else
      redirect_to @court, alert: @photo.errors.full_messages.to_sentence.presence || t("courts.photos.review_failed")
    end
  end

  def reject
    return head :forbidden unless current_user&.admin?

    if @photo.reject_by!(current_user)
      redirect_to @court, notice: t("courts.photos.rejected_notice")
    else
      redirect_to @court, alert: t("courts.photos.review_failed")
    end
  end

  def destroy
    unless current_user&.admin? || @photo.user_id == current_user.id
      return head :forbidden
    end

    @photo.destroy
    redirect_to @court, notice: t("courts.photos.deleted_notice")
  end

  private

  def set_court
    @court = Court.find(params[:court_id])
  end

  def set_photo
    @photo = @court.court_photos.find(params[:id])
  end

  def photo_params
    params.fetch(:court_photo, {}).permit(:file)
  end
end
