require "test_helper"
require "support/cache_helper"

class Telegram::ChatRelayTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include CacheHelper

  setup do
    @court = Court.create!(name: "Relay Court", city_name: "Yekaterinburg")
    @owner = User.create!(email: "relay_owner_#{SecureRandom.hex(4)}@example.com", name: "Owner", telegram_chat_id: unique_chat_id)
    @player = User.create!(email: "relay_player_#{SecureRandom.hex(4)}@example.com", name: "Player", telegram_chat_id: unique_chat_id)
    # Участник без бота: доставить ему некуда, и он не должен ломать рассылку.
    @silent = User.create!(email: "relay_silent_#{SecureRandom.hex(4)}@example.com", name: "NoBot")
    @game = Game.create!(court: @court, user: @owner, date: Date.current, kind: "game")
    @participation = Participation.create!(game: @game, user: @player, status: "approved", approved_at: Time.current)
    Participation.create!(game: @game, user: @silent, status: "approved", approved_at: Time.current)
  end

  teardown do
    @game&.destroy
    [ @owner, @player, @silent ].compact.each(&:destroy)
    @court&.destroy
  end

  test "fan-out reaches every member with a bot except the sender" do
    delivered = []
    stub_singleton(Telegram::DeliverChatMessageJob, :perform_later, ->(game_id, recipient_id, text) { delivered << [ game_id, recipient_id, text ] }) do
      Telegram::RelayChatMessageJob.perform_now(@game.id, @player.id, "во сколько завтра?")
    end

    assert_equal [ @owner.id ], delivered.map { |row| row[1] }
    assert_match "во сколько завтра?", delivered.first[2]
    assert_match "Player", delivered.first[2]
  end

  test "a sender who already left the squad is not relayed" do
    @participation.destroy

    delivered = 0
    stub_singleton(Telegram::DeliverChatMessageJob, :perform_later, ->(*) { delivered += 1 }) do
      Telegram::RelayChatMessageJob.perform_now(@game.id, @player.id, "привет")
    end

    assert_equal 0, delivered
  end

  test "delivery sends plain text without parse_mode" do
    params = nil
    stub_singleton(Telegram::Api, :post, ->(_path, sent) { params = sent; { "ok" => true } }) do
      Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, "текст с _подчёркиванием_ и [скобкой")
    end

    assert_equal @owner.telegram_chat_id.to_s, params["chat_id"]
    assert_equal "текст с _подчёркиванием_ и [скобкой", params["text"]
    assert_not params.key?("parse_mode")
  end

  # Ответ в том же окне — первое, что делает получатель. Раньше он пропадал:
  # у человека не было указателя, и Relay не знал, в какую игру его отдать.
  test "delivery turns the chat mode on for a recipient who has none" do
    params = nil

    with_memory_cache do
      stub_singleton(Telegram::Api, :post, ->(_path, sent) { params = sent; { "ok" => true } }) do
        Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, "во сколько?")
      end

      assert_equal @game.id, Telegram::Chat::Session.active_game(@owner.telegram_chat_id, @owner).id
    end

    buttons = JSON.parse(params["reply_markup"])["inline_keyboard"].first
    assert_equal [ "chat:pick", "chat:exit" ], buttons.map { |button| button["callback_data"] }
  end

  test "delivery leaves an existing chat choice alone" do
    other = Game.create!(court: @court, user: @owner, date: Date.current, kind: "game")
    params = nil

    with_memory_cache do
      Telegram::Chat::Session.start(@owner.telegram_chat_id, other)

      stub_singleton(Telegram::Api, :post, ->(_path, sent) { params = sent; { "ok" => true } }) do
        Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, "во сколько?")
      end

      assert_equal other.id, Telegram::Chat::Session.game_id(@owner.telegram_chat_id)
    end

    assert_not params.key?("reply_markup")
  ensure
    other&.destroy
  end

  test "a later automatic delivery becomes the reply target" do
    other = Game.create!(court: @court, user: @owner, date: Date.current, kind: "game")
    second_delivery = nil

    with_memory_cache do
      stub_singleton(Telegram::Api, :post, ->(*) { { "ok" => true } }) do
        Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, "из первой игры")
      end

      stub_singleton(Telegram::Api, :post, ->(_path, sent) { second_delivery = sent; { "ok" => true } }) do
        Telegram::DeliverChatMessageJob.perform_now(other.id, @owner.id, "из второй игры")
      end

      assert_equal other.id, Telegram::Chat::Session.active_game(@owner.telegram_chat_id, @owner).id
    end

    assert second_delivery.key?("reply_markup")
  ensure
    other&.destroy
  end

  test "a failed delivery leaves no chat mode behind" do
    # 403 — постоянная ошибка: сообщение с кнопками до человека не дошло, и
    # оказаться в чате втихаря он не должен.
    with_memory_cache do
      stub_singleton(Telegram::Api, :post, ->(*) { { "ok" => false, "error_code" => 403, "description" => "Forbidden" } }) do
        Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, "во сколько?")
      end

      assert_nil Telegram::Chat::Session.game_id(@owner.telegram_chat_id)
    end
  end

  test "a throttled delivery arms nothing and sends the buttons again on the retry" do
    throttled = { "ok" => false, "error_code" => 429, "parameters" => { "retry_after" => 7 } }
    later = Class.new { def perform_later(*) = true }.new
    second_attempt = nil

    with_memory_cache do
      stub_singleton(Telegram::Api, :post, ->(*) { throttled }) do
        stub_singleton(Telegram::DeliverChatMessageJob, :set, ->(wait:) { later }) do
          Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, "во сколько?")
        end
      end

      assert_nil Telegram::Chat::Session.game_id(@owner.telegram_chat_id)

      stub_singleton(Telegram::Api, :post, ->(_path, sent) { second_attempt = sent; { "ok" => true } }) do
        Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, "во сколько?")
      end

      assert_equal @game.id, Telegram::Chat::Session.game_id(@owner.telegram_chat_id)
    end

    assert second_attempt.key?("reply_markup")
  end

  test "a retried server error leaves no chat mode behind" do
    with_memory_cache do
      assert_enqueued_jobs 1, only: Telegram::DeliverChatMessageJob do
        stub_singleton(Telegram::Api, :post, ->(*) { { "ok" => false, "error_code" => 503 } }) do
          Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, "во сколько?")
        end
      end

      assert_nil Telegram::Chat::Session.game_id(@owner.telegram_chat_id)
    end
  end

  # Указатель на игру, которой больше нет, — мусор: он не должен навсегда
  # запирать включение чата для живой игры.
  test "a stale pointer does not block arming the chat mode" do
    other = Game.create!(court: @court, user: @owner, date: Date.current, kind: "game")
    params = nil

    with_memory_cache do
      Telegram::Chat::Session.start(@owner.telegram_chat_id, other)
      other.destroy

      stub_singleton(Telegram::Api, :post, ->(_path, sent) { params = sent; { "ok" => true } }) do
        Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, "во сколько?")
      end

      assert_equal @game.id, Telegram::Chat::Session.active_game(@owner.telegram_chat_id, @owner).id
    end

    assert params.key?("reply_markup")
  end

  # Отправка не мгновенна: пока она идёт, человек мог сам открыть другую игру.
  test "a choice made while the message was in flight is not overwritten" do
    other = Game.create!(court: @court, user: @owner, date: Date.current, kind: "game")

    with_memory_cache do
      posting = lambda do |*|
        Telegram::Chat::Session.start(@owner.telegram_chat_id, other)
        { "ok" => true }
      end

      stub_singleton(Telegram::Api, :post, posting) do
        Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, "во сколько?")
      end

      assert_equal other.id, Telegram::Chat::Session.game_id(@owner.telegram_chat_id)
    end
  ensure
    other&.destroy
  end

  test "stale validation does not delete a concurrent explicit choice" do
    stale = Game.create!(court: @court, user: @owner, date: Date.current, kind: "game")
    fresh = Game.create!(court: @court, user: @owner, date: Date.current, kind: "game")

    with_memory_cache do
      Telegram::Chat::Session.start(@owner.telegram_chat_id, stale)
      stale.destroy

      lookup = lambda do |**|
        Telegram::Chat::Session.start(@owner.telegram_chat_id, fresh)
        nil
      end
      stub_singleton(Game, :find_by, lookup) do
        assert_nil Telegram::Chat::Session.active_game(@owner.telegram_chat_id, @owner)
      end

      assert_equal fresh.id, Telegram::Chat::Session.game_id(@owner.telegram_chat_id)
    end
  ensure
    fresh&.destroy
    stale&.destroy
  end

  test "delivery re-checks membership right before sending" do
    @participation.destroy

    sent = 0
    stub_singleton(Telegram::Api, :post, ->(*) { sent += 1; { "ok" => true } }) do
      Telegram::DeliverChatMessageJob.perform_now(@game.id, @player.id, "привет")
    end

    assert_equal 0, sent
  end

  test "delivery reschedules itself on a 429" do
    rescheduled = nil
    throttled = { "ok" => false, "error_code" => 429, "parameters" => { "retry_after" => 7 } }
    later = Class.new { def perform_later(*) = true }.new

    stub_singleton(Telegram::Api, :post, ->(*) { throttled }) do
      stub_singleton(Telegram::DeliverChatMessageJob, :set, ->(wait:) { rescheduled = wait; later }) do
        Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, "привет")
      end
    end

    assert_equal 7.seconds, rescheduled
  end

  test "delivery retries a server error" do
    assert_enqueued_jobs 1, only: Telegram::DeliverChatMessageJob do
      stub_singleton(Telegram::Api, :post, ->(*) { { "ok" => false, "error_code" => 503 } }) do
        Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, "привет")
      end
    end
  end

  test "delivery retries when Telegram does not respond" do
    assert_enqueued_jobs 1, only: Telegram::DeliverChatMessageJob do
      stub_singleton(Telegram::Api, :post, ->(*) { nil }) do
        Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, "привет")
      end
    end
  end

  test "delivery does not retry a permanent client error" do
    assert_no_enqueued_jobs only: Telegram::DeliverChatMessageJob do
      stub_singleton(Telegram::Api, :post, ->(*) { { "ok" => false, "error_code" => 403, "description" => "Forbidden" } }) do
        Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, "привет")
      end
    end
  end

  private

  def unique_chat_id
    @chat_id_seq = (@chat_id_seq || 0) + 1
    910_000_000 + (Process.pid % 10_000) * 100 + @chat_id_seq
  end
end
