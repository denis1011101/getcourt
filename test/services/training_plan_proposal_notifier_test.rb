require "test_helper"

class TrainingPlanProposalNotifierTest < ActiveSupport::TestCase
  test "asks the organiser to decide and shows the proposed plan" do
    setup_training
    texts = []

    stub_singleton(SendTelegramNotificationJob, :perform_later, ->(chat_id, text, **) { texts << [ chat_id, text ] }) do
      TrainingPlanProposalNotifier.approval_requested(@proposal)
    end

    chat_id, text = texts.sole
    assert_equal @owner.telegram_chat_id, chat_id
    assert_includes text, "Правка плана тренировки от @player_ivan"
    assert_includes text, "Новый план: Подача, Разминка"
    assert_includes text, "Комментарий: Больше подачи"
    assert_includes text, "/games/#{@game.id}"
  end

  test "sends the vote with buttons to everyone who comes to the court" do
    setup_training
    @proposal.approve!
    calls = []

    stub_singleton(Telegram::Api, :send_with_buttons, ->(*args, **) { calls << args }) do
      TrainingPlanProposalNotifier.vote_started(@proposal)
    end

    chat_id, text, keyboard = calls.sole
    assert_equal @owner.telegram_chat_id, chat_id
    assert_includes text, "Голосование за правку плана"
    assert_equal [ "game:plan_vote:#{@proposal.id}:yes", "game:plan_vote:#{@proposal.id}:no" ],
                 keyboard.first.map { |button| button[:callback_data] }
  end

  test "tells the players how the vote ended" do
    setup_training
    @proposal.approve!
    @proposal.vote!(@owner, true)
    texts = []

    stub_singleton(SendTelegramNotificationJob, :perform_later, ->(chat_id, text, **) { texts << [ chat_id, text ] }) do
      TrainingPlanProposalNotifier.settled(@proposal)
    end

    assert_predicate @proposal, :applied?
    assert_equal [ @owner.telegram_chat_id, @player.telegram_chat_id ].sort, texts.map(&:first).sort
    assert texts.all? { |_, text| text.include?("План тренировки обновлён") }
  end

  private
    def setup_training
      @owner = create_member("plan-notify-owner", 95_001)
      @player = create_member("plan-notify-player", 95_002, telegram_username: "player_ivan")
      @game = Game.create!(court: courts(:one), user: @owner, date: Date.tomorrow, time: "18:00", kind: "training")
      @game.participations.create!(user: @player, status: "approved")
      warmup = TrainingBlock.create!(user: @owner, title: "Разминка")
      serve = TrainingBlock.create!(user: @player, title: "Подача")
      @proposal = @game.training_plan_proposals.create!(
        user: @player,
        training_block_ids: [ serve.id, warmup.id ],
        mode: "vote",
        comment: "Больше подачи"
      )
    end

    def create_member(prefix, chat_id, telegram_username: nil)
      User.create!(
        email: "#{prefix}-#{SecureRandom.hex(4)}@example.com",
        telegram_chat_id: chat_id,
        telegram_username: telegram_username,
        telegram_locale: "ru",
        notification_channel: "telegram"
      )
    end
end
