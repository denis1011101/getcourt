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
end
