require "test_helper"
require "net/http"

class Social::BlueskyPostingServiceTest < ActiveSupport::TestCase
  CREDENTIALS = { "BLUESKY_IDENTIFIER" => "getcourt.bsky.social", "BLUESKY_APP_PASSWORD" => "app-pass" }.freeze

  class FakeHttp
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def request(request)
      @requests << request
      respond(request.uri.path.split("/").last)
    end

    def get(path)
      @requests << path
      respond("image")
    end

    private

    def respond(key)
      @responses.fetch(key) { raise "unexpected request: #{key}" }
    end
  end

  setup do
    @content = Social::Content::Welcome.new
  end

  test "not configured without credentials" do
    with_env("BLUESKY_IDENTIFIER" => nil, "BLUESKY_APP_PASSWORD" => nil) do
      assert_not Social::BlueskyPostingService.configured?
    end
  end

  test "logs in, uploads the image and returns the post uri" do
    http = FakeHttp.new(
      "com.atproto.server.createSession" => json_response({ accessJwt: "jwt", did: "did:plc:test" }),
      "image" => binary_response("x" * 100, "image/png"),
      "com.atproto.repo.uploadBlob" => json_response({ blob: { "$type" => "blob", "size" => 100 } }),
      "com.atproto.repo.createRecord" => json_response({ uri: "at://did:plc:test/app.bsky.feed.post/abc" })
    )

    uri = with_stubbed_http(http) { post }

    assert_equal "at://did:plc:test/app.bsky.feed.post/abc", uri

    record = created_record(http)
    assert_equal "app.bsky.feed.post", record["$type"]
    assert_equal [ "en" ], record["langs"]
    assert_equal "app.bsky.embed.images", record["embed"]["$type"]
    assert record["facets"].any? { |facet| facet["features"].first["$type"].end_with?("#link") }
  end

  test "an image over the blob limit is dropped but the post still goes out" do
    http = FakeHttp.new(
      "com.atproto.server.createSession" => json_response({ accessJwt: "jwt", did: "did:plc:test" }),
      "image" => binary_response("x" * (Social::BlueskyPostingService::MAX_BLOB_BYTES + 1), "image/png"),
      "com.atproto.repo.createRecord" => json_response({ uri: "at://did:plc:test/app.bsky.feed.post/abc" })
    )

    uri = with_stubbed_http(http) { post }

    assert_equal "at://did:plc:test/app.bsky.feed.post/abc", uri
    assert_nil created_record(http)["embed"]
  end

  test "a failed image fetch does not take the post down with it" do
    http = FakeHttp.new(
      "com.atproto.server.createSession" => json_response({ accessJwt: "jwt", did: "did:plc:test" }),
      "image" => Net::HTTPNotFound.new("1.1", "404", "Not Found"),
      "com.atproto.repo.createRecord" => json_response({ uri: "at://did:plc:test/app.bsky.feed.post/abc" })
    )

    assert_equal "at://did:plc:test/app.bsky.feed.post/abc", with_stubbed_http(http) { post }
  end

  test "returns nothing when the session cannot be created" do
    http = FakeHttp.new(
      "com.atproto.server.createSession" => Net::HTTPUnauthorized.new("1.1", "401", "Unauthorized")
    )

    assert_nil with_stubbed_http(http) { post }
  end

  private

  def post
    Social::BlueskyPostingService.new(content: @content, locale: :en).call
  end

  def created_record(http)
    request = http.requests.reverse.find { |candidate| candidate.respond_to?(:uri) && candidate.uri.path.end_with?("createRecord") }
    JSON.parse(request.body)["record"]
  end

  def with_stubbed_http(http, &block)
    with_env(CREDENTIALS) do
      stub_singleton(Net::HTTP, :start, ->(*, **, &inner) { inner.call(http) }, &block)
    end
  end

  def json_response(payload)
    build_response(Net::HTTPOK, payload.to_json, "application/json")
  end

  def binary_response(body, content_type)
    build_response(Net::HTTPOK, body, content_type)
  end

  def build_response(klass, body, content_type)
    response = klass.new("1.1", "200", "OK")
    response["content-type"] = content_type
    response.instance_variable_set(:@read, true)
    response.instance_variable_set(:@body, body)
    response
  end
end
