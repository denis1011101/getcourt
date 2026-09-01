require "test_helper"

class Telegram::ChatRelayTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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
