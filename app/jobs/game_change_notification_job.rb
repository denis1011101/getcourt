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
      pending = Rails.cache.read(key)
      merged = merge_changes(pending&.fetch("changes", nil) || {}, tracked)

      # `touched_at` moves with every edit so the delivery trails the last one:
      # an editing session longer than the debounce used to get a partial message
      # now and the rest in a second one.
      Rails.cache.write(key, { "changes" => merged, "touched_at" => Time.current }, expires_in: 1.hour)

      set(wait: DEBOUNCE).perform_later(game.id, actor&.id) if pending.blank?
    end

    def cache_key(game_id, actor_id)
      "game:pending_changes:#{game_id}:#{actor_id}"
    end

    # How much of the debounce is left after the last edit. Zero means the editing
    # has settled down and the collected changes can go out.
    def remaining_debounce(touched_at)
      return 0 if touched_at.blank?

      [ DEBOUNCE.to_i - (Time.current - touched_at), 0.0 ].max
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
    pending = Rails.cache.read(key)
    return if pending.blank?

    # Still editing: wait out the tail instead of sending half of the changes now.
    remaining = self.class.remaining_debounce(pending["touched_at"])
    if remaining.positive?
      self.class.set(wait: remaining).perform_later(game_id, actor_id)
      return
    end

    changes = pending["changes"]
    Rails.cache.delete(key)
    return if changes.blank?

    GameChangeNotifier.notify(game: game, actor: User.find_by(id: actor_id), changes: changes)
  end
end
