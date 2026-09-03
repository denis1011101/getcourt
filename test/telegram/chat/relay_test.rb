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

    assert_equal [ @game.id, @player.id, "привет", nil ], enqueued&.first(4)
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

  # Отыгранная игра живёт в базе до еженедельной чистки, и состав вместе с ней:
  # обсудить её после матча — обычное дело, поэтому чат закрывается не концом
  # дня игры, а сбросом.
  test "a played game keeps its chat until the weekly reset" do
    enqueued = nil

    in_chat_mode do
      @game.update_columns(date: Date.current - 2, recurring: false)

      stub_singleton(Telegram::RelayChatMessageJob, :perform_later, ->(*args) { enqueued = args }) do
        assert Telegram::Chat::Relay.handle_message(tg_message("привет"))
      end
      assert_equal @game.id, Telegram::Chat::Session.game_id(@player.telegram_chat_id)
    end

    assert_equal [ @game.id, @player.id, "привет", nil ], enqueued&.first(4)
  end

  test "a deleted game closes the chat mode" do
    in_chat_mode do
      @game.destroy

      stub_singleton(Telegram::RelayChatMessageJob, :perform_later, ->(*) { flunk "игры больше нет" }) do
        assert_not Telegram::Chat::Relay.handle_message(tg_message("привет"))
      end
      assert_nil Telegram::Chat::Session.game_id(@player.telegram_chat_id)
    end
  end

  test "a photo is relayed with its caption" do
    enqueued = nil

    attached = nil

    in_chat_mode do
      stub_singleton(Telegram::RelayChatMessageJob, :perform_later, ->(*args) { enqueued = args }) do
        stub_singleton(Telegram::AttachChatMediaJob, :perform_later, ->(*args) { attached = args }) do
          photo = tg_message(nil, message_id: 900).merge(
            "photo" => [ { "file_id" => "small" }, { "file_id" => "large" } ],
            "caption" => "вот корт"
          )
          assert Telegram::Chat::Relay.handle_message(photo)
        end
      end
    end

    assert_equal [ @game.id, @player.id, "вот корт", { "kind" => "photo", "file_id" => "large" } ], enqueued.first(4)
    assert_equal [ @game.id, @player.id, { "kind" => "photo", "file_id" => "large" }, "вот корт" ], attached
    assert_equal "#{@player.telegram_chat_id}:900", enqueued.last
  end

  test "a sticker without any caption is relayed too" do
    enqueued = nil

    in_chat_mode do
      stub_singleton(Telegram::RelayChatMessageJob, :perform_later, ->(*args) { enqueued = args }) do
        # Стикеру место в переписке, а не в галерее игры.
        stub_singleton(Telegram::AttachChatMediaJob, :perform_later, ->(*) { flunk "стикер в игру не кладём" }) do
          sticker = tg_message(nil, message_id: 901).merge("sticker" => { "file_id" => "stk" })
          assert Telegram::Chat::Relay.handle_message(sticker)
        end
      end
    end

    assert_equal [ @game.id, @player.id, "", { "kind" => "sticker", "file_id" => "stk" } ], enqueued.first(4)
  end

  test "what the chat cannot carry is answered instead of being silently dropped" do
    said = nil

    in_chat_mode do
      stub_singleton(Telegram::Api, :send_simple, ->(_chat_id, text, **_kw) { said = text }) do
        stub_singleton(Telegram::RelayChatMessageJob, :perform_later, ->(*) { flunk "гео пересылать нечем" }) do
          location = tg_message(nil, message_id: 902).merge("location" => { "latitude" => 56.8, "longitude" => 60.6 })
          assert Telegram::Chat::Relay.handle_message(location)
        end
      end
    end

    assert_equal Telegram::I18n.t(:chat_unsupported), said
  end

  # Регрессия: ретранслятор был написан, но живой путь сообщения его не звал —
  # UpdateService уходит в MainMenuProcessor, а тот знал только /start и
  # /register. Режим чата включался, а текст пропадал молча.
  test "text typed in the bot reaches the relay through the live update path" do
    enqueued = nil

    in_chat_mode do
      stub_singleton(Telegram::RelayChatMessageJob, :perform_later, ->(*args) { enqueued = args }) do
        Telegram::UpdateService.process({ "message" => tg_message("привет") })
      end
    end

    assert_equal [ @game.id, @player.id, "привет", nil ], enqueued&.first(4)
  end

  # Тот же живой путь, что и у текста: у вложения text пустой, и раньше на
  # этом месте сообщение упиралось в разбор команд.
  test "a photo sent to the bot reaches the relay through the live update path" do
    enqueued = nil

    in_chat_mode do
      stub_singleton(Telegram::RelayChatMessageJob, :perform_later, ->(*args) { enqueued = args }) do
        photo = tg_message(nil).merge("photo" => [ { "file_id" => "live" } ])
        Telegram::UpdateService.process({ "message" => photo })
      end
    end

    assert_equal({ "kind" => "photo", "file_id" => "live" }, enqueued&.fetch(3))
  end

  test "an unknown command is not relayed into the game chat" do
    enqueued = []

    in_chat_mode do
      stub_singleton(Telegram::RelayChatMessageJob, :perform_later, ->(*args) { enqueued << args }) do
        Telegram::UpdateService.process({ "message" => tg_message("/menu") })
      end
    end

    assert_empty enqueued
  end

  test "the chat command opens chat mode through the live update path" do
    started = []

    with_memory_cache do
      stub_singleton(Telegram::Chat::Flow, :start, ->(chat_id, user) { started << [ chat_id, user.id ] }) do
        Telegram::UpdateService.process({ "message" => tg_message("/chat") })
      end
    end

    assert_equal [ [ @player.telegram_chat_id.to_s, @player.id ] ], started
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
