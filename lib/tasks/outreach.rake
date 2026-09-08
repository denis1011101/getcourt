namespace :outreach do
  desc "Import contacts from a file (rake outreach:import[list.txt]); one `email` or `email,Name` per line"
  task :import, [ :path ] => :environment do |_task, args|
    path = args[:path]

    if path.blank? || !File.exist?(path)
      puts "Usage: rake outreach:import[path/to/list.txt]"
      next
    end

    added = OutreachContact.import(File.readlines(path))
    puts "Imported #{added} contacts, #{OutreachContact.pending.count} waiting to be sent"
  end

  desc "Send today's batch right now (rake outreach:send_batch[10]); never goes over the daily limit"
  task :send_batch, [ :limit ] => :environment do |_task, args|
    limit = args[:limit].presence&.to_i || OutreachContact::DAILY_BATCH
    sent = OutreachEmailJob.perform_now(limit)
    puts "Sent #{sent}, #{OutreachContact.pending.count} contacts left"
  end

  desc "Show how the outreach list is doing"
  task status: :environment do
    puts "total: #{OutreachContact.count}"
    puts "sent: #{OutreachContact.where.not(sent_at: nil).count}"
    puts "pending: #{OutreachContact.pending.count}"
    puts "today: #{OutreachContact.daily_limit_taken.count} of #{OutreachContact::DAILY_BATCH}"
    puts "unsubscribed: #{OutreachContact.where.not(unsubscribed_at: nil).count}"
    failed = OutreachContact.where(sent_at: nil).where.not(last_error: nil)
    failed.find_each { |contact| puts "failed (#{contact.attempts}): #{contact.email} — #{contact.last_error}" }
  end
end
