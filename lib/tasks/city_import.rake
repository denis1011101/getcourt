namespace :import do
  desc "Import GeoNames cities file. Usage: rake import:geonames FILE=./cities1000.txt"
  task geonames: :environment do
    file = ENV["FILE"] || "./cities1000.txt"
    raise "Specify FILE=path" unless File.exist?(file)

    batch = []
    batch_size = 1000
    cols = %i[geonameid name asciiname alternatenames latitude longitude feature_class feature_code country_code cc2 admin1 admin2 admin3 admin4 population elevation dem timezone mod_date]

    File.open(file, "r:UTF-8").each_with_index do |line, i|
      fields = line.chomp.split("\t")
      tz = fields[17] # timezone column per GeoNames format
      batch << {
        geoname_id: fields[0].to_i,
        name: fields[1],
        asciiname: fields[2],
        country_code: fields[8],
        latitude: fields[4],
        longitude: fields[5],
        population: fields[14].to_i,
        timezone: tz,
        created_at: Time.current,
        updated_at: Time.current
      }

      if batch.size >= batch_size
        City.insert_all(batch, unique_by: :geoname_id)
        batch.clear
      end
    end

    City.insert_all(batch) unless batch.empty?
    puts "Import done"
  end
end
