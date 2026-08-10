class CourtSuggestionRejectionsController < ApplicationController
  def create
    return head :forbidden unless current_user&.admin?

    suggestion = CourtSuggestion.find(params[:court_suggestion_id])
    if suggestion.reject_by!(current_user)
      redirect_to court_suggestion_path(suggestion), notice: t("courts.suggestions.rejected")
    else
      redirect_to court_suggestion_path(suggestion), alert: t("courts.suggestions.review_failed")
    end
  end
end
