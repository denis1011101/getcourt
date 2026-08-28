class TrainingPlanVote < ApplicationRecord
  belongs_to :training_plan_proposal
  belongs_to :user

  validates :user_id, uniqueness: { scope: :training_plan_proposal_id }
end
