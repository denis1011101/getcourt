class GameChangeNotificationJob < ApplicationJob
  queue_as :default

  DEBOUNCE = 2.minutes

  class << self
    # Bot edits land one field per click, so notifying on each save would send five
    # messages for one edit. Changes are collected under a single key and delivered
    # once the editing settles down.
    def schedule(game, actor, changes)
      tracked = (changes || {}).slice(*GameChangeNotifier::TRACKED_FIELDS)
      return if tracked.empty?

      key = cache_key(game.id, actor&.id)
      pending = Rails.cache.read(key) || {}
      Rails.cache.write(key, merge_changes(pending, tracked), expires_in: 1.hour)

      set(wait: DEBOUNCE).perform_later(game.id, actor&.id) if pending.empty?
    end

    def cache_key(game_id, actor_id)
      "game:pending_changes:#{game_id}:#{actor_id}"
    end

    # Keep the value the participant last saw as "from" and the newest one as "to";
    # a field edited back to where it started is not a change at all.
    def merge_changes(pending, incoming)
      incoming.each_with_object(pending.dup) do |(field, (from, to)), merged|
        from = merged[field].first if merged.key?(field)
        merged[field] = [ from, to ]
        merged.delete(field) if from == to
      end
    end
  end

  def perform(game_id, actor_id)
    game = Game.find_by(id: game_id)
    return unless game

    key = self.class.cache_key(game_id, actor_id)
    changes = Rails.cache.read(key)
    return if changes.blank?

    Rails.cache.delete(key)
    GameChangeNotifier.notify(game: game, actor: User.find_by(id: actor_id), changes: changes)
  end
end
