require "test_helper"
require "securerandom"

class TournamentsFlowJoinModerationTest < ActiveSupport::TestCase
  def setup
    suffix = SecureRandom.hex(4)
    @owner = User.create!(email: "owner-#{suffix}@example.com", name: "Owner", telegram_chat_id: "9001")
    @guest = User.create!(email: "guest-#{suffix}@example.com", name: "Guest", telegram_chat_id: "9002")
    @court = Court.create!(name: "Court #{suffix}", moderation_status: "approved", approved_at: Time.current)
    @tournament = Tournament.create!(user: @owner, name: "Tour #{suffix}", players_count: 8, format: "singles", start_date: Date.current)
    @tournament.courts << @court
  end

  test "regular join creates pending request and owner approval approves it" do
    send_api_calls = []

    with_stubbed_singleton_method(Telegram::Api, :answer_callback, true) do
      with_stubbed_singleton_method(Telegram::Api, :send_api, ->(*args) { send_api_calls << args; { "ok" => true } }) do
        with_stubbed_singleton_method(Telegram::Api, :send_simple, true) do
          with_stubbed_singleton_method(Telegram::Handlers::TournamentsHandler, :show_tournament, true) do
            Telegram::Flows::TournamentsFlow.handle_callback(callback(@guest.telegram_chat_id, "cb-join", "tournament:join:#{@tournament.id}:1"))
          end
        end
      end
    end

    participant = TournamentParticipant.find_by(tournament: @tournament, user: @guest)
    assert participant.present?
    assert_equal "pending", participant.status
    assert_nil participant.approved_at
    assert send_api_calls.any? { |api, payload| api == "sendMessage" && payload[:text].to_s.include?("##{@tournament.id}") }

    with_stubbed_singleton_method(Telegram::Api, :answer_callback, true) do
      with_stubbed_singleton_method(Telegram::Api, :send_api, true) do
        with_stubbed_singleton_method(Telegram::Api, :send_simple, true) do
          Telegram::Flows::TournamentsFlow.handle_callback(callback(@owner.telegram_chat_id, "cb-approve", "tournament:approve_participation:#{participant.id}", 777))
        end
      end
    end

    participant.reload
    assert_equal "approved", participant.status
    assert participant.approved_at.present?
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
