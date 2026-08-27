require "test_helper"

class GameInvitationDeliveryTest < ActiveSupport::TestCase
  test "invites to a training, names the coach and shows the programme" do
    text = invitation_text(training: true)

    assert_includes text, "С тренером Иван Петров"
    assert_includes text, "Программа: Разминка, Подача"
    assert_includes text, "Вас приглашают на тренировку:"
    assert_includes text, "Приглашает Пётр Организатор."
  end

  test "invites to a game without a programme" do
    text = invitation_text(training: false)

    assert_includes text, "Вас приглашают в игру:"
    assert_not_includes text, "Программа:"
  end

  test "names the court so the invitee knows where to come" do
    text = invitation_text(training: false)

    assert_includes text, "Корт: #{courts(:one).name}"
  end

  test "keeps whole blocks in a long programme instead of cutting a word" do
    text = invitation_text(training: true, blocks: (1..40).map { |i| "Блок номер #{i} на технику" })

    assert_not_includes text, "..."
    assert_includes text, "Блок номер 1 на технику"
    assert_match(/\+ ещё \d+/, text)
  end

  private
    def invitation_text(training:, blocks: [ "Разминка", "Подача" ])
      coach = User.create!(
        email: "invite-coach@example.com",
        name: "Иван Петров",
        coach: true
      )
      inviter = users(:two)
      inviter.update!(email: "inviter@example.com", name: "Пётр Организатор")
      invitee = users(:one)
      invitee.update!(
        email: "invitee@example.com",
        telegram_chat_id: 94_001,
        telegram_locale: "ru",
        notification_channel: "telegram"
      )
      game = Game.create!(
        court: courts(:one),
        user: inviter,
        date: Date.tomorrow,
        time: "18:00",
        with_coach: training,
        coach: (coach if training)
      )
      if training
        block_ids = blocks.map { |title| TrainingBlock.create!(user: coach, title: title).id }
        game.replace_training_plan!(block_ids)
      end
      calls = []

      stub_singleton(Telegram::Api, :send_with_buttons, ->(*args, **) { calls << args }) do
        GameInvitationDelivery.new(game: game, inviter: inviter, game_url: "https://getcourt.co/games/#{game.id}")
          .deliver(user: invitee)
      end

      calls.first.second
    end
end
