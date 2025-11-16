namespace :telegram do
  desc "Send daily telegram reminders (tomorrow and today)"
  task send_daily: :environment do
    DailyTelegramNotificationsJob.perform_now(1) # tomorrow reminders
    DailyTelegramNotificationsJob.perform_now(0) # today reminders
  end
end
