class AddOnboardingDismissedAtToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :onboarding_dismissed_at, :datetime
  end
end
