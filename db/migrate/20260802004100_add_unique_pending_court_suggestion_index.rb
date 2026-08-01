class AddUniquePendingCourtSuggestionIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :court_suggestions,
      %i[court_id user_id],
      unique: true,
      where: "status = 'pending'",
      name: "index_unique_pending_court_suggestions"
  end
end
