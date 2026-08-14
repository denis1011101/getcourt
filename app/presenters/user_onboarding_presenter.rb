class UserOnboardingPresenter
  Item = Data.define(:key, :completed, :path)

  attr_reader :user

  def initialize(user:, routes: Rails.application.routes.url_helpers)
    @user = user
    @routes = routes
  end

  # Hidden once everything is done, or once the newcomer says they are done with it.
  def visible?
    user.present? && !user.onboarding_dismissed? && items.any? { |item| !item.completed }
  end

  def items
    @items ||= [
      Item.new(key: :city, completed: user.city_name.present?, path: @routes.profile_account_path),
      Item.new(key: :telegram, completed: user.telegram_chat_id.present?, path: @routes.notifications_account_path),
      Item.new(key: :sport, completed: sport_chosen?, path: @routes.profile_account_path),
      Item.new(key: :game, completed: playing?, path: @routes.new_game_path)
    ].freeze
  end

  def completed_count
    items.count(&:completed)
  end

  def total_count
    items.size
  end

  def progress_percent
    return 100 if total_count.zero?

    (completed_count * 100.0 / total_count).round
  end

  private

  def sport_chosen?
    user.preferred_sports.to_a.any? || user.skill_levels.to_h.any? || user.skill_level.present?
  end

  def playing?
    user.games.exists? || user.participations.exists?
  end
end
