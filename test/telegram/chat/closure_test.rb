require "test_helper"
require "support/cache_helper"

class Telegram::Chat::ClosureTest < ActiveSupport::TestCase
  include StubHelper
  include CacheHelper

  setup do
    @court = Court.create!(name: "Closure Court", city_name: "Yekaterinburg")
    @owner = User.create!(email: "closure_owner_#{SecureRandom.hex(4)}@example.com", name: "Owner", telegram_chat_id: 910_300_001)
    @player = User.create!(email: "closure_player_#{SecureRandom.hex(4)}@example.com", name: "Player", telegram_chat_id: 910_300_002)
    @game = Game.create!(court: @court, user: @owner, date: Date.current, kind: "game")
    Participation.create!(game: @game, user: @player, status: "approved", approved_at: Time.current)
  end

  teardown do
    @game&.destroy
    [ @owner, @player ].compact.each(&:destroy)
    @court&.destroy
  end

  # Второго захода по этим людям не будет: состав уже сброшен, а игра удалена.
  # Значит, упавшая отправка одному не вправе ни оставить остальных в мёртвом
  # чате, ни съесть их письма.
  test "a failed notice strands neither the rest of the squad nor their sessions" do
    with_memory_cache do
      Telegram::Chat::Session.start(@owner.telegram_chat_id.to_s, @game)
      Telegram::Chat::Session.start(@player.telegram_chat_id.to_s, @game)

      sent = []
      broken = @owner.telegram_chat_id.to_s
      stub_singleton(SendTelegramNotificationJob, :perform_later, lambda { |chat_id, _text|
        raise "telegram is down" if chat_id == broken

        sent << chat_id
      }) do
        assert_equal 1, Telegram::Chat::Closure.notify(@game, :chat_closed_finished)
      end

      assert_equal [ @player.telegram_chat_id.to_s ], sent
      assert_nil Telegram::Chat::Session.active_game(@owner.telegram_chat_id.to_s, @owner)
      assert_nil Telegram::Chat::Session.active_game(@player.telegram_chat_id.to_s, @player)
    end
  end
end
