require "test_helper"

class SocialTest < ActiveJob::TestCase
  class ConfiguredAdapter
    def self.configured? = true
  end

  class UnconfiguredAdapter
    def self.configured? = false
  end

  setup do
    @court = Court.create!(name: "Social Court", city_name: "Yekaterinburg")
    @owner = User.create!(email: "social_owner@example.com", telegram_chat_id: "990001")
    @game = Game.create!(court: @court, user: @owner, date: Date.current + 2, time: "19:00",
                         sport: "Tennis", players_count: 4)
  end

  test "publishes to every configured network and to no other" do
    with_adapters("bluesky" => ConfiguredAdapter, "nostr" => ConfiguredAdapter, "threads" => UnconfiguredAdapter) do
      assert_enqueued_jobs 2, only: PostSocialJob do
        Social.publish(Social::Content::Welcome.new)
      end
    end

    networks = enqueued_networks
    assert_equal %w[bluesky nostr], networks.sort
  end

  test "an urgent search that is off publishes nothing" do
    with_adapters("bluesky" => ConfiguredAdapter) do
      assert_no_enqueued_jobs only: PostSocialJob do
        Social.publish_urgent(@game)
      end
    end
  end

  test "turning the search on from the web publishes the announcement" do
    with_adapters("bluesky" => ConfiguredAdapter) do
      assert_enqueued_jobs 1, only: PostSocialJob do
        @game.update!(urgent_player_search: true)
      end
    end
  end

  # Дыра, ради которой публикация переехала на модель: раньше телеграм-бот
  # включал срочный поиск, а наружу не уходило ничего.
  test "turning the search on from the telegram bot publishes it too" do
    callback = {
      "id" => "cb-1",
      "from" => { "id" => @owner.telegram_chat_id },
      "message" => { "chat" => { "id" => @owner.telegram_chat_id }, "message_id" => 7 },
      "data" => "game:urgent_search:#{@game.id}:on:1"
    }

    with_adapters("bluesky" => ConfiguredAdapter) do
      assert_enqueued_jobs 1, only: PostSocialJob do
        stub_singleton(Telegram::Api, :answer_callback, ->(*) { true }) do
          stub_singleton(Telegram::Handlers::GamesHandler, :show_game, ->(*, **) { nil }) do
            Telegram::Flows::Games::Manage::UrgentSearchFlow.handle_callback(callback)
          end
        end
      end
    end

    assert @game.reload.urgent_player_search?
  end

  test "app_host tolerates a scheme in APP_HOST" do
    with_env("APP_HOST" => "https://getcourt.ru/") do
      assert_equal "getcourt.ru", Social.app_host
      assert_equal "https://getcourt.ru/og-image.png", Social.app_url("/og-image.png")
    end
  end

  private

  def enqueued_networks
    enqueued_jobs.select { |job| job["job_class"] == "PostSocialJob" }.map { |job| job["arguments"].last }
  end

  def with_adapters(mapping, &block)
    stub_singleton(Social, :adapter_for, ->(network) { mapping.fetch(network.to_s, UnconfiguredAdapter) }, &block)
  end
end
