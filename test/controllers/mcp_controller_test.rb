require "test_helper"

class McpControllerTest < ActionDispatch::IntegrationTest
  TOKEN = "test-mcp-token".freeze

  test "is invisible while no token is configured" do
    with_token(nil) do
      post mcp_url, params: request_body("tools/list"), headers: json_headers

      assert_response :not_found
    end
  end

  test "turns away a caller without the right token" do
    with_token(TOKEN) do
      post mcp_url, params: request_body("tools/list"), headers: json_headers
      assert_response :unauthorized

      post mcp_url, params: request_body("tools/list"), headers: json_headers("Bearer wrong")
      assert_response :unauthorized
    end
  end

  test "answers a tools/list from an authorised caller" do
    with_token(TOKEN) do
      post mcp_url, params: request_body("tools/list"), headers: json_headers("Bearer #{TOKEN}")

      assert_response :success
      names = JSON.parse(response.body).dig("result", "tools").map { |tool| tool["name"] }
      assert_equal %w[search_games get_game], names
    end
  end

  test "reports malformed JSON as a parse error" do
    with_token(TOKEN) do
      post mcp_url, params: "{not json", headers: json_headers("Bearer #{TOKEN}")

      assert_response :bad_request
      assert_equal Mcp::Server::PARSE_ERROR, JSON.parse(response.body).dig("error", "code")
    end
  end

  test "acknowledges a notification with 202 and an empty body" do
    with_token(TOKEN) do
      post mcp_url,
        params: { jsonrpc: "2.0", method: "notifications/initialized" }.to_json,
        headers: json_headers("Bearer #{TOKEN}")

      assert_response :accepted
      assert_empty response.body
    end
  end

  test "handles a batch and drops the notifications from the answer" do
    with_token(TOKEN) do
      batch = [
        { jsonrpc: "2.0", id: 1, method: "ping" },
        { jsonrpc: "2.0", method: "notifications/initialized" }
      ]
      post mcp_url, params: batch.to_json, headers: json_headers("Bearer #{TOKEN}")

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal 1, body.size
      assert_equal 1, body.first["id"]
    end
  end

  private

  def json_headers(authorization = nil)
    headers = { "CONTENT_TYPE" => "application/json" }
    headers["Authorization"] = authorization if authorization
    headers
  end

  def request_body(method)
    { jsonrpc: "2.0", id: 1, method: method }.to_json
  end

  def with_token(token)
    previous = ENV["MCP_TOKEN"]
    token.nil? ? ENV.delete("MCP_TOKEN") : ENV["MCP_TOKEN"] = token
    yield
  ensure
    previous.nil? ? ENV.delete("MCP_TOKEN") : ENV["MCP_TOKEN"] = previous
  end
end
