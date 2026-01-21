class CreateCities < ActiveRecord::Migration[8.0]
  def change
    create_table :cities do |t|
      t.integer :geoname_id
      t.string  :name
      t.string  :asciiname
      t.string  :country_code
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.integer :population
      t.string  :timezone
      t.timestamps
    end

    add_index :cities, :name
    add_index :cities, :country_code
    add_index :cities, :timezone
    add_index :cities, :geoname_id, unique: true
  end
end
