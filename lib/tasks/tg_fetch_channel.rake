# Rake tasks to fetch Telegram channels/posts
namespace :tg do
  desc "Import gist posts into telegram_posts (what the Tennis Life feed reads). Run from cron."
  task import_gist_posts: :environment do
    puts "Imported gist posts: #{TennisLife::GistPostImporter.call}"
  end

  desc "Enqueue daily fetch for all Telegram channels"
  task fetch_all: :environment do
    FetchAllTelegramChannelsJob.perform_later
    puts "Enqueued FetchAllTelegramChannelsJob"
  end

  desc "Fetch a single channel immediately. Usage: rake tg:fetch[username] or CHANNEL=username rake tg:fetch"
  task :fetch, [ :username ] => :environment do |t, args|
    username = (args[:username] || ENV["CHANNEL"]).to_s.strip
    raise "Provide channel username (e.g. nogirune)" if username.blank?
    username = username.sub(/^@/, "")
    ch = TelegramChannel.find_or_create_by!(username: username) do |c|
      c.url = "https://t.me/#{username}"
      c.title = username
    end
    FetchTelegramChannelJob.perform_now(ch.id)
    puts "Fetched channel #{ch.username} (id=#{ch.id})"
  end

  desc "Enqueue fetch for a channel by id. Usage: rake tg:enqueue[ID]"
  task :enqueue, [ :id ] => :environment do |t, args|
    id = (args[:id] || ENV["CHANNEL_ID"]).to_i
    raise "Provide channel id" if id <= 0
    FetchTelegramChannelJob.perform_later(id)
    puts "Enqueued FetchTelegramChannelJob for channel id=#{id}"
  end
end
