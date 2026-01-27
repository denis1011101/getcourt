class PlayerStatisticsController < ApplicationController
  before_action :set_user

  def show
    @stats = @user.player_statistic || @user.create_player_statistic
    matches = Match.where(user: @user).includes(:opponent, :game).order(played_at: :desc).limit(5).to_a
    related_ids = matches.flat_map do |m|
      s = (m.stats || {}).to_h
      [ m.opponent_id, s["partner_id"], *Array(s["opponent_ids"]) ]
    end.compact.uniq

    names_by_id =
      if related_ids.any?
        User.where(id: related_ids).map { |u| [ u.id, (u.name.to_s.strip.presence || u.telegram_username.to_s.strip.presence || u.email.to_s) ] }.to_h
      else
        {}
      end

    render partial: "player_statistics/modal", locals: { user: @user, stats: @stats, matches: matches, names_by_id: names_by_id }
  end

  private

  def set_user
    @user = User.find(params[:user_id] || params[:id])
  end
end
