module AccessControl
  # Общая проверка права управления (admin || owner)
  def self.can_manage?(user, record)
    return false unless user
    return true if user.admin?
    return true if record.respond_to?(:user) && record.user == user
    return true if record.respond_to?(:user_id) && record.user_id == user.id
    false
  end

  # Можно ли actor удалить участника (self | game owner | admin)
  def self.can_remove_participant?(actor, game, participation_user)
    return false unless actor
    return true if actor.admin?
    return true if game.respond_to?(:user) && game.user == actor
    return true if actor == participation_user
    false
  end
end
