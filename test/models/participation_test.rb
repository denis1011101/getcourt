require "test_helper"
require "support/cache_helper"

class ParticipationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include CacheHelper
  test "is invalid when same user joins same game twice" do
    duplicate = Participation.new(user: participations(:one).user, game: participations(:one).game)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already joined this game"
  end

  test "requires status" do
    participation = Participation.new(user: users(:one), game: games(:two), status: nil)

    assert_not participation.valid?
    assert_includes participation.errors[:status], "can't be blank"
  end

  test "guest is valid without user" do
    participation = Participation.new(game: games(:one), guest_name: "Alex Guest", status: "approved")

    assert participation.valid?
    assert participation.guest?
    assert_equal "Alex Guest", participation.display_name
  end

  test "registered participation cannot have guest name" do
    participation = Participation.new(user: users(:one), game: games(:two), guest_name: "Alex Guest")

    assert_not participation.valid?
    assert_includes participation.errors[:guest_name], "must be blank"
  end

  test "registered participation requires existing user" do
    participation = Participation.new(user_id: 987_654_321, game: games(:two), status: "approved")

    assert_not participation.valid?
    assert_includes participation.errors[:user], "can't be blank"
  end

  test "guest name is unique per game case-insensitively" do
    Participation.create!(game: games(:one), guest_name: "Alex Guest", status: "approved")
    duplicate = Participation.new(game: games(:one), guest_name: "alex guest", status: "approved")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:guest_name], "has already been taken"
  end

  test "guest name is limited to 50 characters" do
    participation = Participation.new(game: games(:one), guest_name: "a" * 51, status: "approved")

    assert_not participation.valid?
    assert_includes participation.errors[:guest_name], "is too long (maximum is 50 characters)"
  end

  test "joining a game turns on chat mode and shows the switch and leave buttons" do
    court = Court.create!(name: "Join Chat Court", city_name: "Yekaterinburg")
    owner = User.create!(email: "join-chat-owner-#{SecureRandom.hex(4)}@example.com", name: "Owner", telegram_chat_id: 910_000_003)
    player = User.create!(email: "join-chat-player-#{SecureRandom.hex(4)}@example.com", name: "Player", telegram_chat_id: 910_000_001)
    game = Game.create!(court: court, user: owner, date: Date.current, kind: "game")
    sent = []

    with_memory_cache do
      stub_singleton(Telegram::Api, :send_with_buttons, ->(*args, **) { sent << args }) do
        perform_enqueued_jobs do
          Participation.create!(game: game, user: player, status: "approved", approved_at: Time.current)
        end
      end

      assert_equal game.id, Telegram::Chat::Session.game_id(player.telegram_chat_id)
    end

    # Карточка уходит и вступившему, и организатору: он в составе, но сам
    # никуда не вступает и иначе остался бы без кнопок.
    assert_equal [ player.telegram_chat_id.to_s, owner.telegram_chat_id.to_s ].sort, sent.map(&:first).sort

    chat_id, text, buttons = sent.find { |args| args.first == player.telegram_chat_id.to_s }
    assert_equal player.telegram_chat_id.to_s, chat_id
    assert_equal [ "chat:pick", "chat:exit" ], buttons.first.map { |button| button[:callback_data] }
    # В счётчике только владелец: себе сообщение не приходит.
    assert_includes text, "(1)"
    assert_includes text, Telegram::I18n.t(:chat_lifetime)
  ensure
    game&.destroy
    [ owner, player ].compact.each(&:destroy)
    court&.destroy
  end

  test "joining enqueues the chat job instead of calling telegram inline" do
    court = Court.create!(name: "Async Chat Court", city_name: "Yekaterinburg")
    owner = User.create!(email: "async-chat-owner-#{SecureRandom.hex(4)}@example.com", name: "Owner")
    player = User.create!(email: "async-chat-player-#{SecureRandom.hex(4)}@example.com", name: "Player", telegram_chat_id: 910_000_004)
    game = Game.create!(court: court, user: owner, date: Date.current, kind: "game")

    stub_singleton(Telegram::Api, :send_with_buttons, ->(*) { flunk "телеграм не должен дёргаться из колбэка" }) do
      assert_enqueued_with(job: Telegram::OpenGameChatJob, args: [ game.id, player.id ]) do
        Participation.create!(game: game, user: player, status: "approved", approved_at: Time.current)
      end
    end
  ensure
    game&.destroy
    [ owner, player ].compact.each(&:destroy)
    court&.destroy
  end

  # Вступают по одному, а организатору карточка уходит на каждое вступление:
  # без этого он получал бы её заново на каждого игрока.
  test "the owner is told about the chat once, not on every join" do
    court = Court.create!(name: "Owner Once Court", city_name: "Yekaterinburg")
    owner = User.create!(email: "once-chat-owner-#{SecureRandom.hex(4)}@example.com", name: "Owner", telegram_chat_id: 910_000_005)
    first = User.create!(email: "once-chat-first-#{SecureRandom.hex(4)}@example.com", name: "First", telegram_chat_id: 910_000_006)
    second = User.create!(email: "once-chat-second-#{SecureRandom.hex(4)}@example.com", name: "Second", telegram_chat_id: 910_000_007)
    game = Game.create!(court: court, user: owner, date: Date.current, kind: "game")
    sent = []

    with_memory_cache do
      stub_singleton(Telegram::Api, :send_with_buttons, ->(*args, **) { sent << args }) do
        perform_enqueued_jobs do
          Participation.create!(game: game, user: first, status: "approved", approved_at: Time.current)
          Participation.create!(game: game, user: second, status: "approved", approved_at: Time.current)
        end
      end
    end

    assert_equal 1, sent.count { |args| args.first == owner.telegram_chat_id.to_s }
  ensure
    game&.destroy
    [ owner, first, second ].compact.each(&:destroy)
    court&.destroy
  end

  # Два вступления сходятся в один момент, и оба колбэка видят пустой
  # указатель: карточку всё равно должен получить только один из них.
  test "two joins at once do not send the owner two cards" do
    court = Court.create!(name: "Race Chat Court", city_name: "Yekaterinburg")
    owner = User.create!(email: "race-chat-owner-#{SecureRandom.hex(4)}@example.com", name: "Owner", telegram_chat_id: 910_000_008)
    game = Game.create!(court: court, user: owner, date: Date.current, kind: "game")
    sent = []

    with_memory_cache do
      stub_singleton(Telegram::Api, :send_with_buttons, ->(*args, **) { sent << args }) do
        stub_singleton(Telegram::Chat::Session, :automatic_start_needed?, ->(*) { true }) do
          2.times { Telegram::Chat::Flow.enter(owner, game) }
        end
      end
    end

    assert_equal 1, sent.size
  ensure
    game&.destroy
    owner&.destroy
    court&.destroy
  end

  test "a join request does not turn on chat mode until it is approved" do
    court = Court.create!(name: "Pending Chat Court", city_name: "Yekaterinburg")
    owner = User.create!(email: "pending-chat-owner-#{SecureRandom.hex(4)}@example.com", name: "Owner")
    player = User.create!(email: "pending-chat-player-#{SecureRandom.hex(4)}@example.com", name: "Player", telegram_chat_id: 910_000_002)
    game = Game.create!(court: court, user: owner, date: Date.current, kind: "game")

    with_memory_cache do
      stub_singleton(Telegram::Api, :send_with_buttons, ->(*) { }) do
        participation = nil
        perform_enqueued_jobs do
          participation = Participation.create!(game: game, user: player, status: "pending")
        end
        assert_nil Telegram::Chat::Session.game_id(player.telegram_chat_id)

        perform_enqueued_jobs do
          participation.update!(status: "approved", approved_at: Time.current)
        end
        assert_equal game.id, Telegram::Chat::Session.game_id(player.telegram_chat_id)
      end
    end
  ensure
    game&.destroy
    [ owner, player ].compact.each(&:destroy)
    court&.destroy
  end
end
