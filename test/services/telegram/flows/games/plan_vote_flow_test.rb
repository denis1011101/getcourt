require "test_helper"

class TelegramGamesPlanVoteFlowTest < ActiveSupport::TestCase
  test "a vote from the chat closes the vote and updates the plan" do
    setup_training
    answers = []

    handled = with_stubbed_api(answers) { Telegram::Flows::Games::PlanVoteFlow.handle_callback(callback("yes")) }

    assert handled
    assert_predicate @proposal.reload, :applied?
    assert_equal [ @serve.id, @warmup.id ], @game.reload.training_block_ids
    assert_equal Telegram::I18n.t(:plan_vote_counted), answers.sole
  end

  test "a vote against leaves the plan alone" do
    setup_training

    with_stubbed_api([]) { Telegram::Flows::Games::PlanVoteFlow.handle_callback(callback("no")) }

    assert_predicate @proposal.reload, :rejected?
    assert_equal [ @warmup.id ], @game.reload.training_block_ids
  end

  test "a closed vote takes no more ballots" do
    setup_training
    @proposal.reject!
    answers = []

    with_stubbed_api(answers) { Telegram::Flows::Games::PlanVoteFlow.handle_callback(callback("yes")) }

    assert_equal Telegram::I18n.t(:plan_vote_closed), answers.sole
    assert_equal 0, @proposal.training_plan_votes.count
  end

  test "someone outside the game is not counted" do
    setup_training
    stranger = User.create!(email: "plan-vote-stranger-#{SecureRandom.hex(4)}@example.com", telegram_chat_id: 96_003)
    answers = []

    with_stubbed_api(answers) do
      Telegram::Flows::Games::PlanVoteFlow.handle_callback(callback("yes", chat_id: stranger.telegram_chat_id))
    end

    assert_equal Telegram::I18n.t(:plan_vote_not_allowed), answers.sole
    assert_predicate @proposal.reload, :voting?
  end

  private
    def setup_training
      @owner = User.create!(email: "plan-vote-owner-#{SecureRandom.hex(4)}@example.com", telegram_chat_id: 96_001)
      @player = User.create!(email: "plan-vote-player-#{SecureRandom.hex(4)}@example.com", telegram_chat_id: 96_002)
      @game = Game.create!(court: courts(:one), user: @owner, date: Date.tomorrow, time: "18:00", kind: "training")
      @game.participations.create!(user: @player, status: "approved")
      @warmup = TrainingBlock.create!(user: @owner, title: "Разминка")
      @serve = TrainingBlock.create!(user: @player, title: "Подача")
      @game.replace_training_plan!([ @warmup.id ])
      @proposal = @game.training_plan_proposals.create!(
        user: @player,
        training_block_ids: [ @serve.id, @warmup.id ],
        mode: "vote",
        status: "voting"
      )
    end

    def callback(answer, chat_id: @owner.telegram_chat_id)
      {
        "id" => "callback-plan-#{answer}",
        "data" => "game:plan_vote:#{@proposal.id}:#{answer}",
        "from" => { "id" => chat_id },
        "message" => { "message_id" => 42, "chat" => { "id" => chat_id } }
      }
    end

    def with_stubbed_api(answers, &block)
      stub_singleton(Telegram::Api, :answer_callback, ->(_id, text = nil, **) { answers << text }) do
        stub_singleton(Telegram::Api, :send_api, ->(*, **) { { "ok" => true } }) do
          stub_singleton(SendTelegramNotificationJob, :perform_later, ->(*, **) { true }, &block)
        end
      end
    end
end
