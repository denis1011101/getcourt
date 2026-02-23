require "test_helper"
require "securerandom"

class TournamentsFlowRoundRobinTest < ActiveSupport::TestCase
  def setup
    suffix = SecureRandom.hex(4)
    @owner = User.create!(email: "owner-rr-#{suffix}@example.com", name: "Owner", telegram_chat_id: "9101")
    @p1 = User.create!(email: "p1-rr-#{suffix}@example.com", name: "P1", telegram_chat_id: "9102")
    @p2 = User.create!(email: "p2-rr-#{suffix}@example.com", name: "P2", telegram_chat_id: "9103")
    @court = Court.create!(name: "RR Court #{suffix}", moderation_status: "approved", approved_at: Time.current)
    @tournament = Tournament.create!(
      user: @owner,
      name: "RR Tour #{suffix}",
      players_count: 8,
      format: "singles",
      tournament_type: "round_robin",
      start_date: Date.current
    )
    @tournament.courts << @court
    TournamentParticipant.create!(tournament: @tournament, user: @p1, name: @p1.name, status: "approved", approved_at: Time.current)
    TournamentParticipant.create!(tournament: @tournament, user: @p2, name: @p2.name, status: "approved", approved_at: Time.current)
  end

  test "round-robin standings are computed correctly from match data" do
    TournamentMatch.create!(
      tournament: @tournament,
      player_a: @p1,
      player_b: @p2,
      score: "6-2 6-4",
      result: "player_a",
      played_at: Time.current
    )
    standings = TournamentStandings.compute(@tournament)
    assert_equal @p1.id, standings.first[:user].id
    assert_equal 1, standings.first[:wins]
    assert_equal 0, standings.first[:losses]
  end

  test "edit tournament name updates tournament" do
    with_stubbed_api do
      locale = Telegram::Helpers::UserLookup.locale_for(@owner.telegram_chat_id)
      t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
      conv = { "flow" => "tournament_edit", "step" => "name", "tournament_id" => @tournament.id, "page" => 1, "message_id" => 123 }
      Telegram::Flows::TournamentsFlow.send(:process_edit_text, @owner.telegram_chat_id, conv, "name", "Updated RR Name", t)
    end

    assert_equal "Updated RR Name", @tournament.reload.name
  end

  test "delete tournament removes record on confirm" do
    with_stubbed_api do
      Telegram::Flows::TournamentsFlow.send(:confirm_delete, @owner.telegram_chat_id, @tournament.id, 1, cb_id: "cb-del", message_id: 123)
    end

    assert_nil Tournament.find_by(id: @tournament.id)
  end

  test "round-robin callback chain pick A/B then score creates tournament match and player matches" do
    with_stubbed_api do
      with_stubbed_conversation_store do
        Telegram::Flows::TournamentsFlow.handle_callback(callback(@owner.telegram_chat_id, "cb-rr-start", "tournament:rr_add_match:#{@tournament.id}:1"))
        Telegram::Flows::TournamentsFlow.handle_callback(callback(@owner.telegram_chat_id, "cb-rr-a", "tournament:rr_pick_a:#{@tournament.id}:#{@p1.id}"))
        Telegram::Flows::TournamentsFlow.handle_callback(callback(@owner.telegram_chat_id, "cb-rr-b", "tournament:rr_pick_b:#{@tournament.id}:#{@p2.id}"))
        handled = Telegram::Flows::TournamentsFlow.process_text(tg_message(@owner.telegram_chat_id, "6-2 6-4"))
        assert_equal true, handled
      end
    end

    tm = TournamentMatch.order(:id).last
    assert tm.present?
    assert_equal @tournament.id, tm.tournament_id
    assert_equal @p1.id, tm.player_a_id
    assert_equal @p2.id, tm.player_b_id
    assert_equal "player_a", tm.result
    assert_equal "6-2 6-4", tm.score

    created_game = Game.order(:id).last
    assert created_game.present?
    assert_equal @tournament.id, created_game.tournament_id
    assert_equal 2, Match.where(game_id: created_game.id).count
  end

  private

  def callback(chat_id, cb_id, data, message_id = 123)
    {
      "id" => cb_id,
      "data" => data,
      "from" => { "id" => chat_id.to_i },
      "message" => {
        "message_id" => message_id,
        "chat" => { "id" => chat_id.to_i }
      }
    }
  end

  def tg_message(chat_id, text, message_id = 999)
    {
      "message_id" => message_id,
      "chat" => { "id" => chat_id.to_i },
      "from" => { "id" => chat_id.to_i },
      "text" => text
    }
  end

  def with_stubbed_api
    with_stubbed_singleton_method(Telegram::Api, :answer_callback, true) do
      with_stubbed_singleton_method(Telegram::Api, :send_simple, true) do
        with_stubbed_singleton_method(Telegram::Api, :send_api, { "ok" => true }) do
          with_stubbed_singleton_method(Telegram::Api, :delete_message, true) do
            with_stubbed_singleton_method(Telegram::Api, :edit_message_with_buttons, { "ok" => true, "result" => { "message_id" => 123 } }) do
              with_stubbed_singleton_method(Telegram::Api, :send_with_buttons, { "ok" => true, "result" => { "message_id" => 123 } }) do
                with_stubbed_singleton_method(Telegram::Handlers::TournamentsHandler, :show_tournament, true) do
                  with_stubbed_singleton_method(Telegram::Handlers::TournamentsHandler, :list_page, true) do
                    yield
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  def with_stubbed_conversation_store
    store = {}
    with_stubbed_singleton_method(Telegram::Helpers::Conversation, :start, ->(chat_id, payload) { store[chat_id.to_s] = payload }) do
      with_stubbed_singleton_method(Telegram::Helpers::Conversation, :get, ->(chat_id) { store[chat_id.to_s] || {} }) do
        with_stubbed_singleton_method(Telegram::Helpers::Conversation, :set, ->(chat_id, payload) { store[chat_id.to_s] = payload }) do
          with_stubbed_singleton_method(Telegram::Helpers::Conversation, :finish, ->(chat_id) { store.delete(chat_id.to_s) }) do
            yield
          end
        end
      end
    end
  end

  def with_stubbed_singleton_method(target, method_name, replacement)
    singleton = target.singleton_class
    had_method = singleton.method_defined?(method_name) || singleton.private_method_defined?(method_name)
    original = singleton.instance_method(method_name) if had_method
    callable = replacement.respond_to?(:call) ? replacement : ->(*) { replacement }

    singleton.define_method(method_name) do |*args, **kwargs, &block|
      callable.call(*args, **kwargs, &block)
    end

    yield
  ensure
    if had_method
      singleton.define_method(method_name, original)
    else
      singleton.remove_method(method_name)
    end
  end
end
