namespace :wallchart do
  desc "Wallchart '26 campaign report: unique people per event and funnel"
  task report: :environment do
    stats = WallchartReport::EVENT_NAMES.index_with { |name| WallchartReport.reach(name) }

    puts format("%-30s %8s %8s %8s %8s", "event", "people", "users", "anon", "total")
    stats.each do |name, s|
      puts format("%-30s %8d %8d %8d %8d", name, s[:people], s[:users], s[:anon], s[:total])
    end

    viewed = stats["wallchart_banner_viewed"][:people]
    clicked = stats["wallchart_banner_clicked"][:people]
    ctr = viewed.zero? ? 0 : (100.0 * clicked / viewed).round(1)
    puts
    puts "Banner CTR: #{ctr}% (#{clicked}/#{viewed} people)"
  end
end
