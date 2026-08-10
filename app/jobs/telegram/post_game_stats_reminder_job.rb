module Telegram
  # Deprecated alias kept for one release: reminders are scheduled hours ahead with
  # `wait_until`, so Solid Queue still holds jobs serialized under the old class name.
  # Delete once no delayed job references it.
  class PostGameStatsReminderJob < ::PostGameStatsReminderJob
  end
end
