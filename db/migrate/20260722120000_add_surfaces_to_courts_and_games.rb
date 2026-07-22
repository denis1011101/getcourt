class AddSurfacesToCourtsAndGames < ActiveRecord::Migration[8.1]
  def change
    # nullable: an empty JSON array serializes to NULL via ActiveRecord's
    # Serialized type; the model coerces NULL back to [] on read (type: Array)
    add_column :courts, :surfaces, :text
    add_column :games, :surface, :string
    add_column :games, :environment, :string
  end
end
