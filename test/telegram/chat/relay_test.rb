require "test_helper"
require "support/cache_helper"

class Telegram::Chat::RelayTest < ActiveSupport::TestCase
  include CacheHelper

  setup do
    @court = Court.create!(name: "Chat Court", city_name: "Yekaterinburg")
    @owner = User.create!(email: "chat_owner_#{SecureRandom.hex(4)}@example.com", name: "Owner", telegram_chat_id: unique_chat_id)
    @player = User.create!(email: "chat_player_#{SecureRandom.hex(4)}@example.com", name: "Player", telegram_chat_id: unique_chat_id)
    @game = Game.create!(court: @court, user: @owner, date: Date.current, kind: "game")
    @participation = Participation.create!(game: @game, user: @player, status: "approved", approved_at: Time.current)
  end

  teardown do
    @game&.destroy
    [ @owner, @player ].compact.each(&:destroy)
    @court&.destroy
  end

  test "relays a message from a player in chat mode" do
    enqueued = nil

    in_chat_mode do
      stub_singleton(Telegram::RelayChatMessageJob, :perform_later, ->(*args) { enqueued = args }) do
        assert Telegram::Chat::Relay.handle_message(tg_message("привет"))
      end
    end

    assert_equal [ @game.id, @player.id, "привет" ], enqueued
  end

  test "ignores a message when chat mode is off" do
    with_memory_cache do
      stub_singleton(Telegram::RelayChatMessageJob, :perform_later, ->(*) { flunk "не должно рассылаться" }) do
        assert_not Telegram::Chat::Relay.handle_message(tg_message("привет"))
      end
    end
  end

  test "a redelivered update is not broadcast twice" do
    calls = 0

    in_chat_mode do
      stub_singleton(Telegram::RelayChatMessageJob, :perform_later, ->(*) { calls += 1 }) do
        # Поллер держит offset в памяти, поэтому после рестарта Telegram отдаёт
        # то же обновление заново.
        2.times { Telegram::Chat::Relay.handle_message(tg_message("привет", message_id: 777)) }
      end
    end

    assert_equal 1, calls
  end

  test "leaving the game closes the chat mode" do
    in_chat_mode do
      @participation.destroy

      stub_singleton(Telegram::RelayChatMessageJob, :perform_later, ->(*) { flunk "выбывший не пишет в игру" }) do
        assert_not Telegram::Chat::Relay.handle_message(tg_message("привет"))
      end
      assert_nil Telegram::Chat::Session.game_id(@player.telegram_chat_id)
    end
  end

  test "a finished game stops accepting messages" do
    in_chat_mode do
      @game.update_columns(date: Date.current - 2, recurring: false)

      stub_singleton(Telegram::RelayChatMessageJob, :perform_later, ->(*) { flunk "игра прошла" }) do
        assert_not Telegram::Chat::Relay.handle_message(tg_message("привет"))
      end
      assert_nil Telegram::Chat::Session.game_id(@player.telegram_chat_id)
    end
  end

  test "media is answered instead of being silently dropped" do
    said = nil

    in_chat_mode do
      stub_singleton(Telegram::Api, :send_simple, ->(_chat_id, text, **_kw) { said = text }) do
        stub_singleton(Telegram::RelayChatMessageJob, :perform_later, ->(*) { flunk "медиа пока не рассылаем" }) do
          photo = tg_message(nil, message_id: 900).merge("photo" => [ { "file_id" => "x" } ])
          assert Telegram::Chat::Relay.handle_message(photo)
        end
      end
    end

    assert_match(/текст/i, said.to_s)
  end

  private

  def in_chat_mode
    with_memory_cache do
      Telegram::Chat::Session.start(@player.telegram_chat_id, @game)
      yield
    end
  end

  # telegram_chat_id — bigint, строковый id молча кастуется в 0.
  def unique_chat_id
    @chat_id_seq = (@chat_id_seq || 0) + 1
    900_000_000 + (Process.pid % 10_000) * 100 + @chat_id_seq
  end

  # Не «message»: так называется метод Minitest::Assertions.
  def tg_message(text, message_id: nil)
    {
      "message_id" => message_id || SecureRandom.random_number(1_000_000),
      "chat" => { "id" => @player.telegram_chat_id },
      "from" => { "id" => @player.telegram_chat_id },
      "text" => text
    }
  end
end
