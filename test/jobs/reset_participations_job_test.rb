require "test_helper"
require "support/cache_helper"

class ResetParticipationsJobTest < ActiveJob::TestCase
  include StubHelper
  include CacheHelper

  setup do
    @owner = users(:one)
    @player = User.create!(email: "reset-player@example.com", notification_channel: "email", locale: "en")
  end

  # Регрессия: пока у задачи не было расписания, это не всплывало. С расписанием
  # в recurring.yml первая же ночь после создания серии вычищала состав игры,
  # которая ещё не состоялась — маркер сброса nil, а next_date в будущем.
  test "keeps the lineup of a series whose first occurrence has not been played" do
    game = Game.create!(
      court: courts(:one),
      user: @owner,
      date: Date.current + 3.days,
      time: "18:00",
      recurring: true
    )
    game.participations.create!(user: @player)

    assert_not game.should_reset_participations?, "серия ещё не отыграна — сбрасывать нечего"

    ResetParticipationsJob.perform_now

    assert_equal 1, game.participations.reload.count
    assert_nil game.reload.last_participations_reset_at
  end

  test "clears the lineup once the previous occurrence has passed" do
    game = Game.create!(
      court: courts(:one),
      user: @owner,
      date: Date.current - 14.days,
      time: "18:00",
      recurring: true
    )
    game.participations.create!(user: @player)

    assert game.should_reset_participations?

    ResetParticipationsJob.perform_now

    assert_empty game.participations.reload
    assert_equal game.next_date, game.reload.last_participations_reset_at
  end

  # Сброс идёт ночью и уносит с собой чат. Без письма человек узнал бы об этом
  # только по тому, что его сообщение никому не дошло, — а оно уходит молча.
  test "tells the players it drops that their chat is gone" do
    player = User.create!(email: "reset-chat@example.com", telegram_chat_id: 910_100_001, telegram_locale: "ru")
    game = Game.create!(
      court: courts(:one), user: @owner, date: Date.current - 14.days, time: "18:00", recurring: true
    )
    game.participations.create!(user: player, status: "approved", approved_at: Time.current)

    sent = []
    with_memory_cache do
      Telegram::Chat::Session.start(player.telegram_chat_id.to_s, game)

      stub_singleton(SendTelegramNotificationJob, :perform_later, ->(chat_id, text, **opts) { sent << [ chat_id, text, opts ] }) do
        ResetParticipationsJob.perform_now
      end

      # Указатель гасим тут же: писать этому составу человек больше не вправе.
      assert_nil Telegram::Chat::Session.active_game(player.telegram_chat_id.to_s, player)
    end

    assert_equal [ player.telegram_chat_id.to_s ], sent.map(&:first)
    assert_match "закрыт", sent.first[1]
    assert_no_match(/translation missing/i, sent.first[1])
    assert_equal({ silent: true }, sent.first[2], "письмо о закрытии чата приходит без звука")
  end

  # Ролик и комментарий живут в игре ровно один цикл: к новой встрече на карточке
  # не должно оставаться ни «сегодня беру мячи», ни видео с прошлой субботы.
  test "clears the comment and the attachments together with the lineup" do
    game = Game.create!(
      court: courts(:one), user: @owner, date: Date.current - 14.days, time: "18:00",
      recurring: true, comment: "сегодня беру мячи"
    )
    medium = create_medium(game)

    ResetParticipationsJob.perform_now

    assert_nil game.reload.comment
    assert_nil GameMedium.find_by(id: medium.id)
  end

  # Файл лежит на диске прода, и место надо освобождать: без снятого вложения
  # сброс копил бы ролики до самой месячной уборки.
  test "detaches the file so Active Storage drops it from disk" do
    game = Game.create!(
      court: courts(:one), user: @owner, date: Date.current - 14.days, time: "18:00", recurring: true
    )
    create_medium(game)

    assert_difference -> { ActiveStorage::Attachment.where(record_type: "GameMedium").count }, -1 do
      ResetParticipationsJob.perform_now
    end
  end

  # Пока цикл не отыгран, сбрасывать нечего — и карточку трогать тоже.
  test "keeps the comment of a series whose occurrence has not been played" do
    game = Game.create!(
      court: courts(:one), user: @owner, date: Date.current + 3.days, time: "18:00",
      recurring: true, comment: "сегодня беру мячи"
    )

    ResetParticipationsJob.perform_now

    assert_equal "сегодня беру мячи", game.reload.comment
  end

  # Маркер сброса закрывает игре повторный заход, поэтому ставить его до уборки
  # нельзя: упавшее удаление ролика иначе не повторилось бы уже никогда.
  test "a failed cleanup leaves the game to the next run" do
    game = Game.create!(
      court: courts(:one), user: @owner, date: Date.current - 14.days, time: "18:00",
      recurring: true, comment: "сегодня беру мячи"
    )
    game.participations.create!(user: @player)
    medium = create_medium(game)

    with_failing_medium_destroy { ResetParticipationsJob.perform_now }

    assert_nil game.reload.last_participations_reset_at, "маркер не ставим, пока уборка не удалась"
    assert_equal 1, game.participations.count, "состав ждёт вместе с игрой"
    assert_not_nil GameMedium.find_by(id: medium.id)

    # Следующая ночь застаёт игру нетронутой и доводит сброс до конца.
    ResetParticipationsJob.perform_now

    assert_empty game.participations.reload
    assert_nil GameMedium.find_by(id: medium.id)
  end

  # Организатор из состава не выпадает — ему закрывать нечего.
  test "leaves the organiser alone" do
    @owner.update_column(:telegram_chat_id, 910_100_002)
    game = Game.create!(
      court: courts(:one), user: @owner, date: Date.current - 14.days, time: "18:00", recurring: true
    )

    sent = []
    with_memory_cache do
      stub_singleton(SendTelegramNotificationJob, :perform_later, ->(chat_id, text, **opts) { sent << [ chat_id, text, opts ] }) do
        ResetParticipationsJob.perform_now
      end
    end

    assert_not_includes sent.map(&:first), @owner.telegram_chat_id.to_s
  end

  private

  SAMPLE_PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=".freeze

  # Неудачу удаления по-другому не подстроить: destroy у вложения падает только
  # на сбое диска или базы.
  def with_failing_medium_destroy
    GameMedium.class_eval do
      alias_method :destroy_without_failure, :destroy
      define_method(:destroy) { false }
    end
    yield
  ensure
    GameMedium.class_eval do
      remove_method :destroy
      alias_method :destroy, :destroy_without_failure
      remove_method :destroy_without_failure
    end
  end

  def create_medium(game)
    medium = GameMedium.new(game: game, user: @owner)
    medium.file.attach(
      io: StringIO.new(Base64.decode64(SAMPLE_PNG)),
      filename: "shot.png",
      content_type: "image/png",
      identify: false
    )
    medium.save!
    medium
  end
end
