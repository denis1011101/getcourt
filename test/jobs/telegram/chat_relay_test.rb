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
    stub_singleton(Telegram::DeliverChatMessageJob, :perform_later, ->(game_id, recipient_id, text, media = nil, origin = nil) { delivered << [ game_id, recipient_id, text, media, origin ] }) do
      Telegram::RelayChatMessageJob.perform_now(@game.id, @player.id, "во сколько завтра?")
    end

    assert_equal [ @owner.id ], delivered.map { |row| row[1] }
    assert_match "во сколько завтра?", delivered.first[2]
    assert_match "Player", delivered.first[2]
  end

  # Шапку собираем на каждого получателя: дата в ней должна читаться на его
  # языке, а не на языке отправителя.
  test "the header date comes in the recipient's locale" do
    @owner.update!(telegram_locale: "en")
    delivered = []

    stub_singleton(Telegram::DeliverChatMessageJob, :perform_later, ->(*args) { delivered << args }) do
      Telegram::RelayChatMessageJob.perform_now(@game.id, @player.id, "во сколько?")
    end

    assert_includes delivered.first[2], I18n.l(@game.next_date, format: :telegram, locale: "en")
  end

  test "an attachment travels by file_id, with the header in the caption" do
    delivered = []
    stub_singleton(Telegram::DeliverChatMessageJob, :perform_later, ->(*args) { delivered << args }) do
      Telegram::RelayChatMessageJob.perform_now(@game.id, @player.id, "вот корт", { "kind" => "photo", "file_id" => "abc" })
    end

    assert_equal({ "kind" => "photo", "file_id" => "abc" }, delivered.first[3])

    params = nil
    path = nil
    stub_singleton(Telegram::Api, :post, ->(sent_path, sent) { path = sent_path; params = sent; { "ok" => true } }) do
      Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, delivered.first[2], delivered.first[3])
    end

    assert_equal "sendPhoto", path
    assert_equal "abc", params["photo"]
    assert_match "вот корт", params["caption"]
    assert_not params.key?("text")
  end

  # Подпись стикеру и кружку Telegram не даёт, а без шапки не видно, кто и в
  # какую игру прислал — поэтому шапка уходит отдельным сообщением перед ними.
  test "a sticker is preceded by the header message" do
    sent = []

    with_memory_cache do
      stub_singleton(Telegram::Api, :post, ->(path, params) { sent << [ path, params ]; { "ok" => true } }) do
        Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, "💬 #1 · Player", { "kind" => "sticker", "file_id" => "stk" })
      end
    end

    assert_equal [ "sendMessage", "sendSticker" ], sent.map(&:first)
    assert_equal "stk", sent.last.last["sticker"]
    # Кнопки — на последнем сообщении, том самом, ради которого всё слалось.
    assert_not sent.first.last.key?("reply_markup")
    assert sent.last.last.key?("reply_markup")
  end

  # Шапка и вложение — два запроса, и второй может упереться в лимит уже после
  # того, как первый ушёл. Повтор джобы приходит с теми же аргументами, поэтому
  # шапку он обязан пропустить, иначе на каждой попытке будет по дублю.
  test "a retry after a throttled attachment does not send the header again" do
    sticker = { "kind" => "sticker", "file_id" => "stk" }
    throttled = { "ok" => false, "error_code" => 429, "parameters" => { "retry_after" => 7 } }
    later = Class.new { def perform_later(*) = true }.new
    sent = []

    with_memory_cache do
      first = lambda do |path, params|
        sent << path
        path == "sendSticker" ? throttled : { "ok" => true }
      end

      stub_singleton(Telegram::Api, :post, first) do
        stub_singleton(Telegram::DeliverChatMessageJob, :set, ->(wait:) { later }) do
          Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, "шапка", sticker, "42:7")
        end
      end

      stub_singleton(Telegram::Api, :post, ->(path, _params) { sent << path; { "ok" => true } }) do
        Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, "шапка", sticker, "42:7")
      end
    end

    assert_equal [ "sendMessage", "sendSticker", "sendSticker" ], sent
  end

  # Шапка не ушла — повторять её обязательно, иначе стикер придёт безымянным.
  test "a retry after a throttled header sends the header again" do
    sticker = { "kind" => "sticker", "file_id" => "stk" }
    throttled = { "ok" => false, "error_code" => 429, "parameters" => { "retry_after" => 7 } }
    later = Class.new { def perform_later(*) = true }.new
    sent = []

    with_memory_cache do
      stub_singleton(Telegram::Api, :post, ->(path, _params) { sent << path; throttled }) do
        stub_singleton(Telegram::DeliverChatMessageJob, :set, ->(wait:) { later }) do
          Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, "шапка", sticker, "42:8")
        end
      end

      stub_singleton(Telegram::Api, :post, ->(path, _params) { sent << path; { "ok" => true } }) do
        Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, "шапка", sticker, "42:8")
      end
    end

    assert_equal [ "sendMessage", "sendMessage", "sendSticker" ], sent
  end

  test "a caption too long for Telegram is trimmed, not dropped" do
    params = nil
    long = "я" * 1500

    with_memory_cache do
      # Чат у получателя уже выбран — приписки не будет, режется только текст.
      Telegram::Chat::Session.start(@owner.telegram_chat_id, @game)

      stub_singleton(Telegram::Api, :post, ->(_path, sent) { params = sent; { "ok" => true } }) do
        Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, long, { "kind" => "video", "file_id" => "vid" })
      end
    end

    assert_equal 1024, params["caption"].length
    assert params["caption"].end_with?("…")
  end

  # Приписка адресована именно новичку в чате — обрезать в подписи надо чужой
  # текст, а не её.
  test "a caption at the limit keeps the lifetime line" do
    params = nil
    long = "я" * 1500

    with_memory_cache do
      stub_singleton(Telegram::Api, :post, ->(_path, sent) { params = sent; { "ok" => true } }) do
        Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, long, { "kind" => "video", "file_id" => "vid" })
      end
    end

    assert_equal 1024, params["caption"].length
    assert params["caption"].end_with?(Telegram::I18n.t(:chat_lifetime))
    assert_includes params["caption"], "…"
  end

  # Перенос по 429 уходит с исходным текстом: иначе приписка копилась бы от
  # попытки к попытке.
  test "a throttled message is rescheduled without the lifetime line baked in" do
    throttled = { "ok" => false, "error_code" => 429, "parameters" => { "retry_after" => 7 } }
    rescheduled = nil
    later = Class.new do
      def initialize(box) = @box = box
      def perform_later(*args) = @box.replace(args)
    end

    with_memory_cache do
      box = []
      stub_singleton(Telegram::Api, :post, ->(*) { throttled }) do
        stub_singleton(Telegram::DeliverChatMessageJob, :set, ->(wait:) { later.new(box) }) do
          Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, "во сколько?")
        end
      end
      rescheduled = box
    end

    assert_equal "во сколько?", rescheduled[2]
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
    assert params["text"].start_with?("текст с _подчёркиванием_ и [скобкой")
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

  # Кому чат включает сама доставка, карточки со сроком жизни он не увидит:
  # строка про субботу должна прийти с первым же сообщением.
  test "the first delivered message says how long the chat lives" do
    params = nil

    with_memory_cache do
      stub_singleton(Telegram::Api, :post, ->(_path, sent) { params = sent; { "ok" => true } }) do
        Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, "во сколько?")
      end

      assert_includes params["text"], Telegram::I18n.t(:chat_lifetime)

      # Второе сообщение — уже без напоминания: чат у человека включён.
      stub_singleton(Telegram::Api, :post, ->(_path, sent) { params = sent; { "ok" => true } }) do
        Telegram::DeliverChatMessageJob.perform_now(@game.id, @owner.id, "в восемь")
      end

      assert_equal "в восемь", params["text"]
    end
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
