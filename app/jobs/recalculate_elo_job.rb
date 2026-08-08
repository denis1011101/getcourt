class RecalculateEloJob < ApplicationJob
  queue_as :default

  # Users::Merge enqueues this from inside the /register transaction, and Solid Queue
  # lives in its own database — without this the worker could start recalculating
  # before the merge is committed and quietly store pre-merge ratings.
  self.enqueue_after_transaction_commit = true

  def perform(modes)
    Array(modes).map(&:to_s).uniq.each do |mode|
      PlayerStatistic.recalculate_elo_for_mode!(mode) if Match::MODES.include?(mode)
    end
  end
end
