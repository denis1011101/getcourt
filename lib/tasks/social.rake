namespace :social do
  desc "Post the welcome message to one network (rake social:welcome[bluesky]) or to all configured ones"
  task :welcome, [ :network ] => :environment do |_task, args|
    content = Social::Content::Welcome.new
    networks = args[:network].present? ? [ args[:network] ] : Social.configured_networks

    if networks.empty?
      puts "No network is configured — set the credentials first."
      next
    end

    networks.each do |network|
      adapter = Social.adapter_for(network)
      unless adapter
        puts "#{network}: unknown network"
        next
      end
      unless adapter.configured?
        puts "#{network}: not configured"
        next
      end

      PostSocialJob.perform_now(content.kind, content.dedup_key, network)
      post = SocialPost.find_by(network: network, kind: content.kind, dedup_key: content.dedup_key)
      puts post ? "#{network}: posted #{post.external_post_id}" : "#{network}: nothing posted, see the log"
    end
  end

  desc "Publish the account profile (rake social:profile[nostr]) — only Nostr needs it, the rest have a UI"
  task :profile, [ :network ] => :environment do |_task, args|
    network = args[:network].presence || "nostr"

    if network != "nostr"
      puts "#{network}: the profile is edited in the network's own app — only nostr has no UI for it"
      next
    end

    unless Social::NostrPostingService.configured?
      puts "nostr: not configured — set NOSTR_SECRET_KEY first."
      next
    end

    id = Social::NostrPostingService.publish_profile
    puts id ? "nostr: profile published #{id}" : "nostr: nothing published, see the log"
  end

  desc "Show what the daily post would say today without publishing it"
  task daily_preview: :environment do
    content = Social::DailyPlanner.new.pick

    if content.nil?
      puts "No fresh material — nothing would be posted today."
      next
    end

    puts "#{content.dedup_key}\n\n#{content.text(locale: :en, limit: Social::BlueskyPostingService::TEXT_LIMIT)}"
    puts "\nimage: #{content.image_url || '—'}"
  end

  desc "Publish today's daily post"
  task daily: :environment do
    PostDailySocialPostJob.perform_now
  end
end
