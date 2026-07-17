class CreateAhoyVisitsAndEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :ahoy_visits do |t|
      t.string :visit_token
      t.string :visitor_token

      t.references :user

      t.string :ip
      t.text :user_agent
      t.text :referrer
      t.string :referring_domain
      t.text :landing_page

      t.string :browser
      t.string :os
      t.string :device_type

      t.string :country
      t.string :region
      t.string :city
      t.float :latitude
      t.float :longitude

      t.string :utm_source
      t.string :utm_medium
      t.string :utm_term
      t.string :utm_content
      t.string :utm_campaign

      t.string :app_version
      t.string :os_version
      t.string :platform

      t.datetime :started_at
    end

    add_index :ahoy_visits, :visit_token, unique: true

    create_table :ahoy_events do |t|
      t.references :visit
      t.references :user

      t.string :name
      t.json :properties
      t.datetime :time
    end

    add_index :ahoy_events, [ :name, :time ]
  end
end
