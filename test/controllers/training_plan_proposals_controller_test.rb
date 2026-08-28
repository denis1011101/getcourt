require "test_helper"

class TrainingPlanProposalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email: "plan-owner-#{SecureRandom.hex(4)}@example.com")
    @player = User.create!(email: "plan-player-#{SecureRandom.hex(4)}@example.com")
    @game = Game.create!(court: courts(:one), user: @owner, date: Date.tomorrow, time: "18:00", kind: "training")
    @game.participations.create!(user: @player, status: "approved")
    @warmup = TrainingBlock.create!(user: @owner, title: "Разминка", shared: true)
    @serve = TrainingBlock.create!(user: @player, title: "Подача")
    @volley = TrainingBlock.create!(user: @owner, title: "Удары с лёта")
    @game.replace_training_plan!([ @warmup.id ])
  end

  test "a participant's change waits for the organiser and is applied by the vote" do
    sign_in_as @player
    post game_training_plan_proposals_url(@game), params: proposal_params(mode: "vote")

    proposal = @game.training_plan_proposals.sole
    assert_predicate proposal, :pending?
    assert_equal [ @warmup.id ], @game.reload.training_block_ids

    sign_in_as @owner
    post approve_game_training_plan_proposal_url(@game, proposal)

    assert_predicate proposal.reload, :voting?
    assert_equal [ @warmup.id ], @game.reload.training_block_ids

    post vote_game_training_plan_proposal_url(@game, proposal), params: { in_favor: "1" }

    assert_predicate proposal.reload, :applied?
    assert_equal [ @serve.id, @warmup.id ], @game.reload.training_block_ids
  end

  test "the vote is lost when the organiser is against it" do
    sign_in_as @player
    post game_training_plan_proposals_url(@game), params: proposal_params(mode: "vote")
    proposal = @game.training_plan_proposals.sole

    sign_in_as @owner
    post approve_game_training_plan_proposal_url(@game, proposal)
    post vote_game_training_plan_proposal_url(@game, proposal), params: { in_favor: "0" }

    assert_predicate proposal.reload, :rejected?
    assert_equal [ @warmup.id ], @game.reload.training_block_ids
  end

  test "the organiser's own change without a vote lands in the plan at once" do
    sign_in_as @owner
    post game_training_plan_proposals_url(@game), params: proposal_params(mode: "direct", block_ids: [ @volley.id, @warmup.id ])

    assert_predicate @game.training_plan_proposals.sole, :applied?
    assert_equal [ @volley.id, @warmup.id ], @game.reload.training_block_ids
  end

  test "an approved change without a vote is applied and does not ask anybody" do
    sign_in_as @player
    post game_training_plan_proposals_url(@game), params: proposal_params(mode: "direct")
    proposal = @game.training_plan_proposals.sole

    sign_in_as @owner
    post approve_game_training_plan_proposal_url(@game, proposal)

    assert_predicate proposal.reload, :applied?
    assert_equal [ @serve.id, @warmup.id ], @game.reload.training_block_ids
  end

  test "the organiser fixes the change before approving it" do
    sign_in_as @player
    post game_training_plan_proposals_url(@game), params: proposal_params(mode: "vote")
    proposal = @game.training_plan_proposals.sole

    sign_in_as @owner
    patch game_training_plan_proposal_url(@game, proposal), params: {
      training_plan_proposal: { training_block_ids: [ @warmup.id, @serve.id ], mode: "direct", comment: "Сначала разминка" }
    }

    proposal.reload
    assert_equal [ @warmup.id, @serve.id ], proposal.training_block_ids
    assert_predicate proposal, :direct?
    assert_predicate proposal, :pending?
  end

  test "a change is rejected by the organiser" do
    sign_in_as @player
    post game_training_plan_proposals_url(@game), params: proposal_params(mode: "vote")
    proposal = @game.training_plan_proposals.sole

    sign_in_as @owner
    post reject_game_training_plan_proposal_url(@game, proposal)

    assert_predicate proposal.reload, :rejected?
    assert_equal [ @warmup.id ], @game.reload.training_block_ids
  end

  test "a stranger neither proposes nor approves" do
    stranger = User.create!(email: "plan-stranger-#{SecureRandom.hex(4)}@example.com")
    sign_in_as stranger

    post game_training_plan_proposals_url(@game), params: proposal_params(mode: "vote")
    assert_response :forbidden
    assert_equal 0, @game.training_plan_proposals.count

    sign_in_as @player
    post game_training_plan_proposals_url(@game), params: proposal_params(mode: "vote")
    proposal = @game.training_plan_proposals.sole

    sign_in_as stranger
    post approve_game_training_plan_proposal_url(@game, proposal)
    assert_response :forbidden
    assert_predicate proposal.reload, :pending?
  end

  test "a stranger does not vote" do
    stranger = User.create!(email: "plan-outsider-#{SecureRandom.hex(4)}@example.com")
    sign_in_as @owner
    post game_training_plan_proposals_url(@game), params: proposal_params(mode: "vote")
    proposal = @game.training_plan_proposals.sole

    sign_in_as stranger
    post vote_game_training_plan_proposal_url(@game, proposal), params: { in_favor: "1" }

    assert_predicate proposal.reload, :voting?
    assert_equal 0, proposal.training_plan_votes.count
  end

  test "the author takes their change back" do
    sign_in_as @player
    post game_training_plan_proposals_url(@game), params: proposal_params(mode: "vote")
    proposal = @game.training_plan_proposals.sole

    assert_difference -> { @game.training_plan_proposals.count }, -1 do
      delete game_training_plan_proposal_url(@game, proposal)
    end
  end

  test "a block from someone else's library never reaches the plan" do
    stranger_block = TrainingBlock.create!(user: User.create!(email: "plan-lib-#{SecureRandom.hex(4)}@example.com"), title: "Чужой блок")
    sign_in_as @player

    post game_training_plan_proposals_url(@game), params: {
      training_plan_proposal: { training_block_ids: [ stranger_block.id, @serve.id ], mode: "vote" }
    }

    assert_equal [ @serve.id ], @game.training_plan_proposals.sole.training_block_ids
  end

  test "the game page shows an open change to the players" do
    sign_in_as @player
    post game_training_plan_proposals_url(@game), params: proposal_params(mode: "vote", comment: "Больше подачи")

    get game_url(@game)

    assert_response :success
    assert_includes response.body, "Больше подачи"
    assert_includes response.body, I18n.t("games.training_plan_proposals.status_pending")
  end

  private
    def sign_in_as(user)
      post session_url, params: { email: user.email }
    end

    def proposal_params(mode:, comment: nil, block_ids: nil)
      {
        training_plan_proposal: {
          training_block_ids: block_ids || [ @serve.id, @warmup.id ],
          mode: mode,
          comment: comment
        }
      }
    end
end
