# Separate migration because CreateAhoyVisitsAndEvents had already been applied
# when the index was first added to it, so the line never ran.
class AddVisitorTokenIndexToAhoyVisits < ActiveRecord::Migration[8.1]
  def change
    add_index :ahoy_visits, :visitor_token
  end
end
