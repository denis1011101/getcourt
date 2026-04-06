class CourtsController < ApplicationController
  include LocationFilters

  before_action :set_court, only: %i[show edit update destroy approve reject]
  skip_before_action :authenticate_user!, only: %i[index show]

  def index
    visible_courts = Court.visible_to(current_user)
    prepare_location_filters(visible_courts.where.not(city_name: [ nil, "" ]).distinct.pluck(:city_name))
    courts = visible_courts.to_a

    if params[:country].present? && params[:city].blank?
      cities_in_country = cities_for_country(params[:country])
      courts = courts.select { |c| cities_in_country.include?(c.city_name) }
    elsif params[:city].present?
      courts = courts.select { |c| c.city_name == params[:city] }
    elsif current_user&.city_name.present?
      user_city = current_user.city_name.downcase
      local, other = courts.partition { |c| c.city_name.to_s.downcase == user_city }
      courts = local + other
    end

    Rails.logger.info "Courts#index current_user_id=#{current_user&.id} courts=#{courts.map { |c| [ c.id, c.user_id ] }.inspect}"
    @pagy, @courts = pagy_array(courts)
  end

  def show
    unless current_user&.admin? || @court.approved?
      redirect_to courts_path, alert: "This court is under moderation." and return
    end
  end

  def new
    @court = Court.new
  end

  def create
    @court = Court.new(court_params)
    normalize_contact_type!(@court)
    @court.user = current_user if current_user.present?
    @court.moderation_status = "pending"
    @court.approved_at = nil
    Rails.logger.info "Courts#create before_save user_id=#{@court.user_id} current_user_id=#{current_user&.id}"

    if @court.save
      Rails.logger.info "Courts#create saved court_id=#{@court.id} user_id=#{@court.user_id}"
      Telegram::AdminNotifier.notify_court_pending(@court, base_url: request.base_url, action: "created")
      redirect_to courts_path, notice: "Your court is under moderation. We will publish it after approval."
    else
      render :new
    end
  end

  def edit
  end

  def update
    @court.assign_attributes(court_params)
    normalize_contact_type!(@court)
    if @court.update(moderation_status: "pending", approved_at: nil)
      Telegram::AdminNotifier.notify_court_pending(@court, base_url: request.base_url, action: "updated")
      redirect_to courts_path, notice: "Your changes are under moderation. We will publish them after approval."
    else
      render :edit
    end
  end

  def approve
    return head :forbidden unless current_user&.admin?

    @court.update(moderation_status: "approved", approved_at: Time.current)
    redirect_to @court, notice: "Court approved."
  end

  def reject
    return head :forbidden unless current_user&.admin?

    @court.update(moderation_status: "rejected", approved_at: nil)
    redirect_to courts_path, notice: "Court rejected."
  end

  def destroy
    unless can_manage?(@court) || (@court.user_id == current_user&.id)
      head :forbidden and return
    end

    @court.destroy
    redirect_to courts_path, notice: "Court was successfully destroyed."
  end

  private

  def set_court
    @court = Court.find(params[:id])
  end

  def court_params
    permitted = params.require(:court).permit(:name, :sport, :coordinates, :user_id, :contact_type, :contact_value, contact_entries: [ :contact_type, :contact_value ])
    contact_entries = permitted.delete(:contact_entries)

    if contact_entries.present?
      prepared_entries = contact_entries.filter_map do |entry|
        type = normalize_contact_type_value(entry[:contact_type])
        value = entry[:contact_value].to_s.strip
        next if value.blank?

        { type: type.presence, value: value }
      end

      permitted[:contact_type] = prepared_entries.first&.dig(:type)
      permitted[:contact_value] = prepared_entries.map { |entry| [ entry[:type], entry[:value] ].compact.join(": ") }.join("\n")
    end

    permitted
  end

  def normalize_contact_type!(court)
    court.contact_type = normalize_contact_type_value(court.contact_type)

    court.contact_value = court.contact_value.to_s.lines.map(&:strip).reject(&:blank?).join("\n")
  end

  def normalize_contact_type_value(value)
    case value.to_s
    when "site"
      "website"
    when "mail"
      "email"
    else
      value.to_s
    end
  end
end
