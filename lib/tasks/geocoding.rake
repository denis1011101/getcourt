namespace :geocoding do
  desc "Fetch Google Maps usage and write to cache (runs Geocoding::FetchGoogleUsageJob)"
  task fetch_usage: :environment do
    result = Geocoding::FetchGoogleUsageJob.perform_now
    puts "Fetched usage: #{result}"
  end

  desc "Backfill city_name for courts that have coordinates but no city"
  task backfill_court_cities: :environment do
    courts = Court.where(city_name: [ nil, "" ]).where.not(coordinates: [ nil, "" ])
    total = courts.count
    puts "Courts to backfill: #{total}"

    courts.find_each.with_index do |court, i|
      Geocoding::FetchCourtAddressJob.perform_later(court.id)
      puts "  [#{i + 1}/#{total}] Enqueued Court##{court.id}"
    end

    puts "Done. All jobs enqueued."
  end
end
