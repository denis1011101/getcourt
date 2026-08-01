namespace :telegram do
  desc "Send daily telegram reminders (tomorrow and today)"
  task send_daily: :environment do
    # Для cron в production выполняем синхронно, чтобы не зависеть от очереди.
    DailyTelegramNotificationsJob.perform_now(1) # tomorrow
    DailyTelegramNotificationsJob.perform_now(0) # today
  end

  desc "Poll Telegram updates (development only). Run: bin/rails telegram:poll"
  task poll: :environment do
    if Rails.env.production?
      puts "Polling disabled in production — use webhook."
      exit 1
    end

    unless ENV["TELEGRAM_BOT_TOKEN"].to_s.present?
      puts "Set TELEGRAM_BOT_TOKEN in your environment to poll."
      exit 1
    end

    poller = Telegram::Poller.new
    puts "Starting Telegram poller (Ctrl-C to stop)..."
    poller.run_loop(poll_interval: 1)
  end

  desc "Update users.telegram_username from Telegram getChat (for users with telegram_chat_id)"
  task update_usernames: :environment do
    Telegram::UpdateTelegramUsernamesJob.perform_now
  end

  desc "Clear bot commands & menu button (bot is invitation-only now)"
  task clear_menu: :environment do
    Telegram::Api.send_api("setMyCommands", { commands: [] })
    Telegram::Api.send_api("setChatMenuButton", { menu_button: { type: "default" } })
  end
end
