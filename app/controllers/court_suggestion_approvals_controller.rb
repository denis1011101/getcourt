class CourtSuggestionApprovalsController < ApplicationController
  def create
    return head :forbidden unless current_user&.admin?

    suggestion = CourtSuggestion.find(params[:court_suggestion_id])
    if suggestion.apply_by!(current_user)
      redirect_to court_suggestion_path(suggestion), notice: t("courts.suggestions.approved")
    else
      redirect_to court_suggestion_path(suggestion), alert: suggestion.errors.full_messages.to_sentence
    end
  end
end
