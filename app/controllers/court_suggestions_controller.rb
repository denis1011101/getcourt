class CourtSuggestionsController < ApplicationController
  before_action :set_court, only: %i[new create]
  before_action :redirect_managers_to_edit, only: %i[new create]
  before_action :require_admin!, only: %i[index show]
  before_action :set_suggestion, only: :show

  def index
    suggestions = CourtSuggestion.order(Arel.sql("CASE status WHEN 'pending' THEN 0 ELSE 1 END"), created_at: :desc)
    @pagy, @court_suggestions = pagy(suggestions)
  end

  def show
  end

  def new
    if current_user.court_suggestions.pending.exists?(court: @court)
      redirect_to @court, alert: t("courts.suggestions.pending_exists")
      return
    end

    prepare_form
  end

  def create
    @proposed_court = @court.dup
    @proposed_court.assign_attributes(editable_params)
    @suggestion = @court.court_suggestions.build(
      user: current_user,
      payload: changed_payload
    )

    if @suggestion.save
      Telegram::AdminNotifier.notify_court_suggestion(@suggestion, base_url: request.base_url)
      redirect_to @court, notice: t("courts.suggestions.created")
    else
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_to @court, alert: t("courts.suggestions.pending_exists")
  end

  private

  def set_court
    @court = Court.find(params[:court_id])
  end

  def set_suggestion
    @suggestion = CourtSuggestion.includes(:court, :user, :reviewed_by).find(params[:id])
  end

  def require_admin!
    head :forbidden unless current_user&.admin?
  end

  def redirect_managers_to_edit
    return unless can_manage?(@court)

    redirect_to edit_court_path(@court)
  end

  def prepare_form
    @suggestion = @court.court_suggestions.build(user: current_user)
    @proposed_court = @court.dup
  end

  def changed_payload
    CourtSuggestion::EDITABLE_FIELDS.each_with_object({}) do |field, payload|
      current_value = normalized_value(@court.public_send(field))
      proposed_value = normalized_value(@proposed_court.public_send(field))
      payload[field] = proposed_value if proposed_value != current_value
    end
  end

  def normalized_value(value)
    value.is_a?(Array) ? value.map(&:to_s).reject(&:blank?).uniq : value
  end

  def editable_params
    permitted = params.require(:court_suggestion).permit(
      :name, :sport, :coordinates, :contact_type, :contact_value, :free, :outdoor, :indoor, :sauna,
      surfaces: [], contact_entries: %i[contact_type contact_value]
    )
    contact_entries = permitted.delete(:contact_entries)

    if contact_entries.present?
      entries = contact_entries.filter_map do |entry|
        value = entry[:contact_value].to_s.strip
        next if value.blank?

        type = normalize_contact_type(entry[:contact_type])
        { type: type.presence, value: value }
      end
      permitted[:contact_type] = entries.first&.dig(:type)
      permitted[:contact_value] = entries.map { |entry| [ entry[:type], entry[:value] ].compact.join(": ") }.join("\n")
    end

    permitted
  end

  def normalize_contact_type(value)
    { "site" => "website", "mail" => "email" }.fetch(value.to_s, value.to_s)
  end
end
