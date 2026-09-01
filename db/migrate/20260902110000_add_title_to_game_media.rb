class AddTitleToGameMedia < ActiveRecord::Migration[8.1]
  def change
    add_column :game_media, :title, :string
  end
end
