class OccurrenceSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_game

  # Одна форма на дату и создаёт, и правит, и сбрасывает: все поля пустые —
  # значит «как в серии», и запись не нужна.
  def create
    return head :forbidden unless current_user.admin? || @game.user == current_user

    date = Date.parse(params[:date].to_s) rescue nil
    return redirect_back(fallback_location: game_path(@game), alert: t("games.occurrence_settings.invalid_date")) unless date

    setting = @game.occurrence_settings.find_or_initialize_by(date: date)
    params[:reset].present? ? setting.assign_attributes(kind: nil, with_coach: nil, coach_id: nil, second_coach_id: nil, guest_coach_name: nil, court_id: nil, without_court: false, players_count: nil) : setting.assign_attributes(setting_params)

    # Форма шлёт тип и галку тренера всегда; совпадающее с серией validate
    # сводит к пустому, и только после этого видно, нужна ли запись вообще.
    setting.validate

    if setting.blank_setting?
      setting.destroy if setting.persisted?
      redirect_to_prebooking_month @game, date, notice: t("games.occurrence_settings.saved")
    elsif setting.save
      redirect_to_prebooking_month @game, date, notice: t("games.occurrence_settings.saved")
    else
      redirect_to_prebooking_month @game, date, alert: setting.errors.full_messages.to_sentence
    end
  end

  private

  def set_game
    @game = Game.find(params[:game_id])
  end

  def setting_params
    attrs = params.fetch(:occurrence_setting, {}).permit(:kind, :with_coach, :coach_id, :second_coach_id, :guest_coach_name, :court_id, :players_count)
    # «Без корта» приходит из того же списка, что и корты.
    without_court = attrs[:court_id] == "none"
    attrs.merge(court_id: (without_court ? nil : attrs[:court_id]), without_court: without_court)
  end
end
