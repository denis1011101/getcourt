class AddCommentToGames < ActiveRecord::Migration[8.0]
  def change
    add_column :games, :comment, :text
  end
end
