module Cities
  class ImportGeoNamesService
    def initialize(file:, batch_size: 1000, min_population: 0)
      @file = file
      @batch_size = batch_size
      @min_population = min_population
    end

    def call
      raise ArgumentError, "File not found: #{@file}" unless File.exist?(@file)

      batch = []
      File.open(@file, "r:BOM|UTF-8").each_line do |line|
        fields = line.chomp.split("\t")
        next if fields.size < 18

        population = fields[14].to_i
        next if population < @min_population

        batch << {
          geoname_id: fields[0].to_i,
          name: fields[1],
          asciiname: fields[2],
          country_code: fields[8],
          latitude: fields[4],
          longitude: fields[5],
          population: population,
          timezone: fields[17],
          created_at: Time.current,
          updated_at: Time.current
        }

        if batch.size >= @batch_size
          City.upsert_all(batch, unique_by: :geoname_id)
          batch.clear
        end
      end

      City.upsert_all(batch, unique_by: :geoname_id) unless batch.empty?
      true
    end
  end
end
