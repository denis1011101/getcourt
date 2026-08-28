class CreateTrainingPlanProposals < ActiveRecord::Migration[8.1]
  def change
    create_table :training_plan_proposals do |t|
      t.references :game, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.string :mode, null: false, default: "vote"
      t.text :comment
      # Правка — это план целиком в нужном порядке, а не разница с текущим:
      # пока предложение ждёт своей очереди, план игры успевает измениться.
      t.json :training_block_ids, null: false, default: []

      t.timestamps
    end

    add_index :training_plan_proposals, [ :game_id, :status ]

    create_table :training_plan_votes do |t|
      t.references :training_plan_proposal, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.boolean :in_favor, null: false

      t.timestamps
    end

    add_index :training_plan_votes, [ :training_plan_proposal_id, :user_id ],
              unique: true, name: "index_training_plan_votes_on_proposal_and_voter"
  end
end
