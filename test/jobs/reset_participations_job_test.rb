require "test_helper"
require "support/cache_helper"

class ResetParticipationsJobTest < ActiveJob::TestCase
  include StubHelper
  include CacheHelper

  # Серия по понедельникам в 18:00: состав понедельника уступает место
  # следующему занятию в четверг в 20:00 — посередине между ними. Время в
  # тестах фиксированное: момент сброса теперь зависит от часа, а не только
  # от даты.
  SERIES_START = Date.new(2026, 8, 31)
  RESET_MOMENT = Time.zone.local(2026, 9, 10, 20, 0)
  NEXT_OCCURRENCE = Date.new(2026, 9, 14)

  setup do
    @owner = users(:one)
    @player = User.create!(email: "reset-player@example.com", notification_channel: "email", locale: "en")
  end

  def weekly_series(**attributes)
    Game.create!({ court: courts(:one), user: @owner, date: SERIES_START, time: "18:00", recurring: true }.merge(attributes))
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

    assert_not game.participations_reset_due?, "серия ещё не отыграна — сбрасывать нечего"

    ResetParticipationsJob.perform_now

    assert_equal 1, game.participations.reload.count
    assert_nil game.reload.last_participations_reset_at
  end

  test "clears the lineup once the previous occurrence has passed" do
    game = weekly_series
    game.participations.create!(user: @player)

    travel_to RESET_MOMENT do
      assert game.participations_reset_due?

      ResetParticipationsJob.perform_now

      assert_empty game.participations.reload
      assert_equal NEXT_OCCURRENCE, game.reload.last_participations_reset_at
    end
  end

  # Корт, который берут на одно занятие, к следующему ещё никто не бронировал:
  # с галкой он уходит вместе с составом, чтобы страница не обещала площадку.
  test "clears the court together with the lineup when the series asks for it" do
    game = weekly_series(release_court_on_reset: true)
    game.participations.create!(user: @player)

    travel_to(RESET_MOMENT) { ResetParticipationsJob.perform_now }

    assert_nil game.reload.court_id
    assert_empty game.participations
  end

  # Маркер сброса закрывает игре повторный заход, поэтому корт снимаем до него:
  # иначе упавшая запись оставила бы старый корт у нового занятия навсегда.
  test "a failed court release leaves the game to the next run" do
    game = weekly_series(release_court_on_reset: true)
    game.participations.create!(user: @player)

    travel_to RESET_MOMENT do
      with_failing_court_release { ResetParticipationsJob.perform_now }

      assert_nil game.reload.last_participations_reset_at, "маркер не ставим, пока корт не снят"
      assert_equal courts(:one), game.court
      assert_equal 1, game.participations.count, "состав ждёт вместе с игрой"

      ResetParticipationsJob.perform_now

      assert_nil game.reload.court_id
      assert_empty game.participations
    end
  end

  # Постоянный состав: люди остаются, но занятие у игры уже следующее — иначе
  # карточка, чат и статистика застряли бы на отыгранном.
  test "rolls a standing group over to the next occurrence without touching the lineup" do
    game = weekly_series(reset_lineup: false, comment: "сегодня беру мячи")
    game.participations.create!(user: @player)

    travel_to RESET_MOMENT do
      assert game.participations_reset_due?

      ResetParticipationsJob.perform_now

      assert_equal [ @player.id ], game.participations.reload.pluck(:user_id)
      assert_equal NEXT_OCCURRENCE, game.reload.last_participations_reset_at
      assert_nil game.comment, "комментарий был про прошедшее занятие"
      assert_not game.participations_reset_due?
    end
  end

  # Поиск игроков без корта невозможен — уведомления идут по городу корта, и
  # модель такую игру не сохранит. Снимаем его вместе с кортом, а не оставляем
  # организатору невалидную игру.
  test "turns off the player search together with the court" do
    game = weekly_series(release_court_on_reset: true, urgent_player_search: true)
    game.participations.create!(user: @player)

    travel_to(RESET_MOMENT) { ResetParticipationsJob.perform_now }

    game.reload
    assert_nil game.court_id
    assert_not game.urgent_player_search?
    assert game.valid?, game.errors.full_messages.to_sentence
  end

  # Корт бронируют на занятие независимо от того, меняются ли люди.
  test "clears the court of a standing group too" do
    game = weekly_series(reset_lineup: false, release_court_on_reset: true)
    game.participations.create!(user: @player)

    travel_to(RESET_MOMENT) { ResetParticipationsJob.perform_now }

    assert_nil game.reload.court_id
    assert_equal 1, game.participations.count
  end

  # Кто бронирует корт на недели вперёд, галку не ставит — по умолчанию корт
  # переживает сброс, как и до появления настройки.
  test "keeps the court by default" do
    game = weekly_series
    game.participations.create!(user: @player)

    travel_to(RESET_MOMENT) { ResetParticipationsJob.perform_now }

    assert_equal courts(:one), game.reload.court
  end

  # Серия «пн + чт»: состав понедельника не может дожить до четверга — в четверг
  # на корт выходит уже другой состав. Середина промежутка — ночь на среду,
  # ближайшие к ней 20:00 — вечер вторника.
  test "a series with two weekdays resets on the evening between them" do
    game = Game.create!(
      court: courts(:one), user: @owner, date: Date.new(2026, 9, 7), time: "18:00",
      recurring: true, recurrence_days: [ 1, 4 ]
    )
    game.participations.create!(user: @player)

    travel_to Time.zone.local(2026, 9, 8, 19, 59) do
      ResetParticipationsJob.perform_now

      assert_equal 1, game.participations.reload.count, "до вечера вторника состав понедельника ещё живёт"
    end

    travel_to Time.zone.local(2026, 9, 8, 20, 0) do
      ResetParticipationsJob.perform_now

      assert_empty game.participations.reload
      assert_equal Date.new(2026, 9, 10), game.reload.last_participations_reset_at
    end
  end

  # У серии раз в неделю промежуток длиннее, и его середина — ночь на пятницу:
  # состав живёт до вечера четверга.
  test "a weekly series resets on the evening halfway to the next occurrence" do
    game = weekly_series
    game.participations.create!(user: @player)

    travel_to Time.zone.local(2026, 9, 9, 20, 0) do
      ResetParticipationsJob.perform_now

      assert_equal 1, game.participations.reload.count, "в среду состав ещё не трогаем"
    end

    travel_to RESET_MOMENT do
      ResetParticipationsJob.perform_now

      assert_empty game.participations.reload
      assert_equal NEXT_OCCURRENCE, game.reload.last_participations_reset_at
    end
  end

  # Человек записывается на конкретный день, а не в очередь: бронь на 17-е
  # никуда не переезжает от того, что 10-е отыграли.
  test "bookings on later dates keep their own dates" do
    booked = User.create!(email: "reset-booked@example.com")
    later = User.create!(email: "reset-booked-later@example.com")
    game = Game.create!(
      court: courts(:one), user: @owner, date: Date.new(2026, 9, 7), time: "18:00",
      recurring: true, recurrence_days: [ 1, 4 ], players_count: 2, prebooking_enabled: true
    )
    game.prebookings.create!(date: Date.new(2026, 9, 10), slot_index: 1, user: booked)
    game.prebookings.create!(date: Date.new(2026, 9, 17), slot_index: 1, user: later)

    travel_to Time.zone.local(2026, 9, 8, 20, 0) do
      ResetParticipationsJob.perform_now
    end

    assert_equal [ booked.id ], game.participations.reload.pluck(:user_id)
    assert_nil game.prebookings.find_by(date: Date.new(2026, 9, 10), slot_index: 1).user_id
    assert_equal later.id, game.prebookings.find_by(date: Date.new(2026, 9, 17), slot_index: 1).user_id
  end

  # Предзапись заведена ради подтверждения организатором: неодобренная заявка
  # не должна попадать в состав в обход него.
  test "a booking waiting for approval is not promoted into the lineup" do
    approved = User.create!(email: "reset-approved@example.com")
    waiting = User.create!(email: "reset-waiting@example.com")
    game = weekly_series(players_count: 2, prebooking_enabled: true)
    game.prebookings.create!(date: NEXT_OCCURRENCE, slot_index: 1, user: approved)
    game.prebookings.create!(date: NEXT_OCCURRENCE, slot_index: 2, user: waiting, status: "pending")

    travel_to RESET_MOMENT do
      ResetParticipationsJob.perform_now
    end

    assert_equal [ approved.id ], game.participations.reload.pluck(:user_id)
  end

  # Сброс уносит с собой чат. Без письма человек узнал бы об этом только по
  # тому, что его сообщение никому не дошло, — а оно уходит молча.
  test "tells the players it drops that their chat is gone" do
    player = User.create!(email: "reset-chat@example.com", telegram_chat_id: 910_100_001, telegram_locale: "ru")
    game = weekly_series
    game.participations.create!(user: player, status: "approved", approved_at: Time.current)

    sent = []
    travel_to RESET_MOMENT do
      with_memory_cache do
        Telegram::Chat::Session.start(player.telegram_chat_id.to_s, game)

        stub_singleton(SendTelegramNotificationJob, :perform_later, ->(chat_id, text, **opts) { sent << [ chat_id, text, opts ] }) do
          ResetParticipationsJob.perform_now
        end

        # Указатель гасим тут же: писать этому составу человек больше не вправе.
        assert_nil Telegram::Chat::Session.active_game(player.telegram_chat_id.to_s, player)
      end
    end

    assert_equal [ player.telegram_chat_id.to_s ], sent.map(&:first)
    assert_match "закрыт", sent.first[1]
    assert_no_match(/translation missing/i, sent.first[1])
    assert_equal({}, sent.first[2], "сброс идёт вечером — письмо приходит со звуком")
  end

  # Чат остаётся тем же, а занятие у него новое: составу об этом говорят, иначе
  # непонятно, про какую игру теперь переписка.
  test "tells the new lineup that the chat moved on to the next game" do
    player = User.create!(email: "reset-chat-updated@example.com", telegram_chat_id: 910_100_003, telegram_locale: "ru")
    game = weekly_series(players_count: 2, prebooking_enabled: true)
    game.prebookings.create!(date: NEXT_OCCURRENCE, slot_index: 1, user: player)

    sent = []
    travel_to RESET_MOMENT do
      with_memory_cache do
        stub_singleton(SendTelegramNotificationJob, :perform_later, ->(chat_id, text, **opts) { sent << [ chat_id, text, opts ] }) do
          ResetParticipationsJob.perform_now
        end
      end
    end

    notice = sent.find { |chat_id, _text, _opts| chat_id == player.telegram_chat_id.to_s }

    assert notice, "тот, кто пришёл в состав из предзаписи, узнаёт об обновлённом чате"
    assert_match "14.09.2026", notice[1]
    assert_match "18:00", notice[1]
    assert_match courts(:one).name, notice[1]
    assert_no_match(/translation missing/i, notice[1])
  end

  # Ролик и комментарий живут в игре ровно один цикл: к новой встрече на карточке
  # не должно оставаться ни «сегодня беру мячи», ни видео с прошлой субботы.
  test "clears the comment and the attachments together with the lineup" do
    game = Game.create!(
      court: courts(:one), user: @owner, date: SERIES_START, time: "18:00",
      recurring: true, comment: "сегодня беру мячи"
    )
    medium = create_medium(game)

    travel_to(RESET_MOMENT) { ResetParticipationsJob.perform_now }

    assert_nil game.reload.comment
    assert_nil GameMedium.find_by(id: medium.id)
  end

  # Файл лежит на диске прода, и место надо освобождать: без снятого вложения
  # сброс копил бы ролики до самой месячной уборки.
  test "detaches the file so Active Storage drops it from disk" do
    game = weekly_series
    create_medium(game)

    assert_difference -> { ActiveStorage::Attachment.where(record_type: "GameMedium").count }, -1 do
      travel_to(RESET_MOMENT) { ResetParticipationsJob.perform_now }
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
      court: courts(:one), user: @owner, date: SERIES_START, time: "18:00",
      recurring: true, comment: "сегодня беру мячи"
    )
    game.participations.create!(user: @player)
    medium = create_medium(game)

    travel_to RESET_MOMENT do
      with_failing_medium_destroy { ResetParticipationsJob.perform_now }

      assert_nil game.reload.last_participations_reset_at, "маркер не ставим, пока уборка не удалась"
      assert_equal 1, game.participations.count, "состав ждёт вместе с игрой"
      assert_not_nil GameMedium.find_by(id: medium.id)

      # Следующий заход застаёт игру нетронутой и доводит сброс до конца.
      ResetParticipationsJob.perform_now

      assert_empty game.participations.reload
      assert_nil GameMedium.find_by(id: medium.id)
    end
  end

  # Организатор из состава не выпадает — закрывать ему нечего. Письмо об
  # обновлённом чате он всё же получает: занятие у чата теперь новое.
  test "leaves the organiser alone" do
    @owner.update_columns(telegram_chat_id: 910_100_002, telegram_locale: "ru")
    weekly_series

    sent = []
    travel_to RESET_MOMENT do
      with_memory_cache do
        stub_singleton(SendTelegramNotificationJob, :perform_later, ->(chat_id, text, **opts) { sent << [ chat_id, text, opts ] }) do
          ResetParticipationsJob.perform_now
        end
      end
    end

    owner_notices = sent.select { |chat_id, _text, _opts| chat_id == @owner.telegram_chat_id.to_s }

    assert_equal 1, owner_notices.size
    assert_match "обновлён", owner_notices.first[1]
  end

  private

  SAMPLE_PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=".freeze

  # Неудачу удаления по-другому не подстроить: destroy у вложения падает только
  # на сбое диска или базы.
  # Роняем именно снятие корта: update_columns с court_id зовёт только оно.
  def with_failing_court_release
    Game.class_eval do
      alias_method :update_columns_without_failure, :update_columns
      define_method(:update_columns) do |attributes|
        raise ActiveRecord::StatementInvalid, "database is locked" if attributes.key?(:court_id)

        update_columns_without_failure(attributes)
      end
    end
    yield
  ensure
    Game.class_eval do
      remove_method :update_columns
      alias_method :update_columns, :update_columns_without_failure
      remove_method :update_columns_without_failure
    end
  end

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
