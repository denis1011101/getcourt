# Дневная пачка холодных писем о брони кортов, см. OutreachContact.
class OutreachEmailJob < ApplicationJob
  queue_as :default

  def perform(limit = OutreachContact::DAILY_BATCH)
    sent = OutreachContact.deliver_daily_batch_now(limit: limit)
    Rails.logger.info "Outreach: sent #{sent}, #{OutreachContact.pending.count} contacts left"
    sent
  end
end
