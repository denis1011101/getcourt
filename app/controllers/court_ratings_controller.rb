class CourtRatingsController < ApplicationController
  before_action :set_court
  before_action :require_verified_user!

  def create
    rating = @court.rating_from(current_user)
    rating.value = params[:value]

    if rating.save
      redirect_to court_path(@court, anchor: "rating"), notice: t("courts.ratings.saved")
    else
      redirect_to court_path(@court, anchor: "rating"), alert: rating.errors.full_messages.to_sentence
    end
  end

  def destroy
    @court.rating_by(current_user)&.destroy
    redirect_to court_path(@court, anchor: "rating"), notice: t("courts.ratings.removed")
  end

  private

  # Тем же набором, что и страница корта: корт на модерации или отклонённый
  # чужим не виден, и копить на нём звёзды до публикации нельзя.
  def set_court
    @court = Court.visible_to(current_user).find(params[:court_id])
  end

  # Подтверждение аккаунта проверяем здесь, а не только в шаблоне: форму со
  # звёздами легко отправить в обход страницы корта.
  def require_verified_user!
    return if current_user.verified?

    session[:verification_return_to] = court_path(@court, anchor: "rating")
    redirect_to new_account_verification_path, alert: t("account_verifications.required")
  end
end
