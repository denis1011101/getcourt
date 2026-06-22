class AddThreadsPostFieldsToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :threads_post_id, :string
    add_column :games, :threads_posted_at, :datetime
  end
end
