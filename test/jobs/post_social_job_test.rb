require "test_helper"

class PostSocialJobTest < ActiveJob::TestCase
  class FakeAdapter
    class << self
      attr_accessor :configured, :result, :calls
    end

    def self.configured? = configured

    def initialize(content:, locale:)
      self.class.calls << { content: content, locale: locale }
    end

    def call = self.class.result
  end

  setup do
    FakeAdapter.configured = true
    FakeAdapter.result = "post-1"
    FakeAdapter.calls = []

    @court = Court.create!(name: "Job Court", city_name: "Yekaterinburg")
    @user = User.create!(email: "job_owner@example.com")
    @game = Game.create!(court: @court, user: @user, date: Date.current + 2, time: "19:00",
                         sport: "Tennis", players_count: 4, urgent_player_search: true)
  end

  test "records the post and passes the network locale to the adapter" do
    assert_difference -> { SocialPost.count }, 1 do
      perform("urgent", "game:#{@game.id}", "bluesky")
    end

    post = SocialPost.last
    assert_equal %w[bluesky urgent post-1], [ post.network, post.kind, post.external_post_id ]
    assert_equal "game:#{@game.id}", post.dedup_key
    assert_equal :en, FakeAdapter.calls.first[:locale]
  end

  test "the same material is not posted to the same network twice" do
    perform("urgent", "game:#{@game.id}", "bluesky")

    assert_no_difference -> { SocialPost.count } do
      perform("urgent", "game:#{@game.id}", "bluesky")
    end
    assert_equal 1, FakeAdapter.calls.size
  end

  test "an unconfigured adapter is never called" do
    FakeAdapter.configured = false

    assert_no_difference -> { SocialPost.count } do
      perform("urgent", "game:#{@game.id}", "bluesky")
    end
    assert_empty FakeAdapter.calls
  end

  test "material that disappeared while the job waited is not posted" do
    @game.update!(urgent_player_search: false)

    assert_no_difference -> { SocialPost.count } do
      perform("urgent", "game:#{@game.id}", "bluesky")
    end
    assert_empty FakeAdapter.calls
  end

  test "an adapter that returned nothing leaves no record" do
    FakeAdapter.result = nil

    assert_no_difference -> { SocialPost.count } do
      perform("urgent", "game:#{@game.id}", "bluesky")
    end
  end

  test "an unknown network is skipped" do
    assert_no_difference -> { SocialPost.count } do
      PostSocialJob.perform_now("urgent", "game:#{@game.id}", "myspace")
    end
  end

  private

  def perform(kind, dedup_key, network)
    stub_singleton(Social, :adapter_for, ->(*) { FakeAdapter }) do
      PostSocialJob.perform_now(kind, dedup_key, network)
    end
  end
end
