namespace :geocoding do
  desc "Fetch Google Maps usage and write to cache (runs Geocoding::FetchGoogleUsageJob)"
  task fetch_usage: :environment do
    result = Geocoding::FetchGoogleUsageJob.perform_now
    puts "Fetched usage: #{result}"
  end
end
