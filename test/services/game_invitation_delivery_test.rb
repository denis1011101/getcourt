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

  test "keeps whole blocks in a long programme instead of cutting a word" do
    text = invitation_text(training: true, blocks: (1..40).map { |i| "Блок номер #{i} на технику" })

    assert_not_includes text, "..."
    assert_includes text, "Блок номер 1 на технику"
    assert_match(/\+ ещё \d+/, text)
  end

  test "makes the court name a link to the court page" do
    text = invitation_text(training: false)

    assert_includes text, %(<a href="https://getcourt.co/courts/#{courts(:one).id}">#{courts(:one).name}</a>)
  end

  test "escapes what people typed so telegram can parse the markup" do
    text = invitation_text(training: false, court_name: "Корт «Смит & сыновья» <1>")

    assert_includes text, "Корт «Смит &amp; сыновья» &lt;1&gt;</a>"
    assert_not_includes text, "<1>"
  end

  test "keeps the email plain: no markup where the text template shows it raw" do
    text = invitation_text(training: false, channel: "email")

    assert_includes text, "Корт: #{courts(:one).name}"
    assert_not_includes text, "<a href"
  end

  test "does not count spots for a training" do
    text = invitation_text(training: true)

    assert_not_includes text, "мест свободно"
    assert_not_includes text, "места свободно"
  end

  test "still counts spots for a game" do
    text = invitation_text(training: false)

    assert_match(/мест[оа]? свободно|места свободно/, text)
  end

  private
    def invitation_text(training:, blocks: [ "Разминка", "Подача" ], court_name: nil, channel: "telegram")
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
        locale: "ru",
        notification_channel: channel
      )
      court = courts(:one)
      court.update!(name: court_name) if court_name
      game = Game.create!(
        court: court,
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
      delivery = GameInvitationDelivery.new(
        game: game,
        inviter: inviter,
        game_url: "https://getcourt.co/games/#{game.id}"
      )

      if channel == "email"
        body = nil
        stub_singleton(UserMailer, :notification, ->(_user, **kwargs) { body = kwargs[:body]; mailer_noop }) do
          delivery.deliver(user: invitee)
        end
        return body
      end

      calls = []
      stub_singleton(Telegram::Api, :send_with_buttons, ->(*args, **) { calls << args }) do
        delivery.deliver(user: invitee)
      end

      calls.first.second
    end

    # UserMailer.notification обычно возвращает письмо, у которого зовут
    # deliver_later — подсовываем заглушку с тем же вызовом.
    def mailer_noop
      Object.new.tap { |o| def o.deliver_later; true; end }
    end
end
