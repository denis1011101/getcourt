require "test_helper"

class TrainingPlanProposalTest < ActiveSupport::TestCase
  test "the plan changes as soon as the majority is for it" do
    proposal = proposal_for(players: 3)
    voters = proposal.voter_ids.map { |id| User.find(id) }

    proposal.approve!
    assert_predicate proposal, :voting?

    proposal.vote!(voters.first, true)
    assert_predicate proposal, :voting?

    proposal.vote!(voters.second, true)
    assert_predicate proposal, :applied?
    assert_equal proposal.training_block_ids, proposal.game.reload.training_block_ids
  end

  test "the change is rejected once it can no longer win" do
    proposal = proposal_for(players: 3)
    voters = proposal.voter_ids.map { |id| User.find(id) }

    proposal.approve!
    proposal.vote!(voters.first, false)
    proposal.vote!(voters.second, false)

    assert_predicate proposal, :rejected?
    assert_equal [ @warmup.id ], proposal.game.reload.training_block_ids
  end

  test "a change with nobody else to ask applies right after approval" do
    proposal = proposal_for(players: 0)

    proposal.approve!

    assert_empty proposal.voter_ids
    assert_predicate proposal, :applied?
  end

  test "a change without a single block makes no sense" do
    proposal = proposal_for(players: 0)

    assert_not proposal.update(training_block_ids: [])
  end

  test "a plain game has no plan to argue about" do
    proposal = proposal_for(players: 0)
    proposal.game.update!(kind: "game", with_coach: false)

    assert_not proposal.reload.valid?
  end

  private
    # Автор правки — организатор, остальные игроки составляют голосующих.
    def proposal_for(players:)
      owner = User.create!(email: "plan-model-owner-#{SecureRandom.hex(4)}@example.com")
      game = Game.create!(court: courts(:one), user: owner, date: Date.tomorrow, time: "18:00", kind: "training")
      players.times do |index|
        player = User.create!(email: "plan-model-player-#{index}-#{SecureRandom.hex(4)}@example.com")
        game.participations.create!(user: player, status: "approved")
      end
      @warmup = TrainingBlock.create!(user: owner, title: "Разминка")
      serve = TrainingBlock.create!(user: owner, title: "Подача")
      game.replace_training_plan!([ @warmup.id ])

      game.training_plan_proposals.create!(user: owner, training_block_ids: [ serve.id, @warmup.id ], mode: "vote")
    end
end
