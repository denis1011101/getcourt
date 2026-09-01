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
