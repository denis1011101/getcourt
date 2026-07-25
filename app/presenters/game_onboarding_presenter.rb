class GameOnboardingPresenter
  Item = Data.define(:key, :completed)

  attr_reader :game, :user

  def initialize(game:, user:)
    @game = game
    @user = user
  end

  def visible?
    owner? && items.any? { |item| !item.completed }
  end

  def items
    @items ||= [
      Item.new(key: :join, completed: joined?),
      Item.new(key: :city, completed: user.city_name.present?),
      Item.new(key: :telegram, completed: user.telegram_chat_id.present?),
      (Item.new(key: :player_search, completed: game.urgent_player_search?) if player_search_relevant?)
    ].compact.freeze
  end

  private

  def owner?
    user.present? && game.user_id == user.id
  end

  def joined?
    game.participations.exists?(user_id: user.id)
  end

  def player_search_relevant?
    !game.tournament_game? && game.next_date.present? && !game.started_for_ui? && spots_available?
  end

  def spots_available?
    required = game.players_count.to_i
    return true unless required.positive?

    participations = game.participations
    taken = participations.respond_to?(:approved) ? participations.approved.count : participations.count
    taken < required
  end
end
