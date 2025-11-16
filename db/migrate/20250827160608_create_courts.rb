class CreateCourts < ActiveRecord::Migration[8.0]
  def change
    create_table :courts do |t|
      t.string :name
      t.string :coordinates

      t.timestamps
    end
  end
end
