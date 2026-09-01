require "test_helper"

class Social::NostrPostingServiceTest < ActiveSupport::TestCase
  SECRET_HEX = "b7e151628aed2a6abf7158809cf4f3c762e7160f38b4da56a784d9045190cfef".freeze

  class FakeRelay
    class << self
      attr_accessor :published, :accepting
    end

    def initialize(*) = nil

    def publish(event)
      self.class.published << event
      self.class.accepting
    end
  end

  setup do
    FakeRelay.published = []
    FakeRelay.accepting = true
    @court = Court.create!(name: "Nostr Court", city_name: "Yekaterinburg", coordinates: "56.8389, 60.6057")
    @user = User.create!(email: "nostr_owner@example.com")
    @game = Game.create!(court: @court, user: @user, date: Date.current + 2, time: "19:00",
                         sport: "Tennis", players_count: 4, urgent_player_search: true)
  end

  test "an nsec key is accepted as well as hex" do
    with_env("NOSTR_SECRET_KEY" => "nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5") do
      assert_equal "67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa",
                   Social::NostrPostingService.secret_key.unpack1("H*")
    end
  end

  test "a key of the wrong length is refused" do
    with_env("NOSTR_SECRET_KEY" => "deadbeef") do
      assert_not Social::NostrPostingService.configured?
    end
  end

  test "publishes a signed note with hashtag and geohash tags" do
    id = publish(Social::Content::UrgentSearch.new(@game))

    note = FakeRelay.published.find { |event| event.kind == 1 }
    assert_equal id, note.id
    assert Social::Nostr::Schnorr.verify([ note.id ].pack("H*"), [ note.pubkey ].pack("H*"), [ note.signature ].pack("H*"))

    assert_includes note.tags, [ "t", "getcourt" ]
    assert_includes note.tags, [ "location", "Nostr Court, Yekaterinburg" ]
    geohashes = note.tags.filter_map { |name, value| value if name == "g" }
    assert_equal 4, geohashes.size
    assert(geohashes.all? { |value| value.start_with?("v65") })
    assert_includes note.content, @game.id.to_s
  end

  test "an upcoming game also goes out as a calendar event" do
    publish(Social::Content::UrgentSearch.new(@game))

    calendar = FakeRelay.published.find { |event| event.kind == 31923 }
    assert_equal [ "d", "urgent-game:#{@game.id}" ], calendar.tags.first
    assert(calendar.tags.any? { |name, _| name == "start" })
    assert(calendar.tags.any? { |name, _| name == "end" })
  end

  test "a post nobody accepted is not counted as published" do
    FakeRelay.accepting = false

    assert_nil publish(Social::Content::Welcome.new)
  end

  private

  def publish(content)
    with_env("NOSTR_SECRET_KEY" => SECRET_HEX, "NOSTR_RELAYS" => "wss://relay.example") do
      stub_singleton(Social::Nostr::Relay, :new, ->(*, **) { FakeRelay.new }) do
        Social::NostrPostingService.new(content: content, locale: :en).call
      end
    end
  end
end
