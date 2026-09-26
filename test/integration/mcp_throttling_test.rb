require "test_helper"

# Лимиты /mcp живут в Rack::Attack, а в тестовой среде кэш — :null_store, поэтому
# на время теста подменяем хранилище на память.
class McpThrottlingTest < ActionDispatch::IntegrationTest
  setup do
    @previous_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    @previous_token = ENV["MCP_TOKEN"]
    ENV["MCP_TOKEN"] = "test-mcp-token"
  end

  teardown do
    Rack::Attack.cache.store = @previous_store
    @previous_token.nil? ? ENV.delete("MCP_TOKEN") : ENV["MCP_TOKEN"] = @previous_token
  end

  test "a burst of calls runs into the limit" do
    20.times { post_mcp(tools_list) }
    assert_response :success

    post_mcp(tools_list)
    assert_response :too_many_requests
  end

  test "an oversized body is turned away before Rails parses it" do
    padding = "x" * Rack::Attack::JSON_BODY_LIMIT
    post_mcp({ jsonrpc: "2.0", id: 1, method: "tools/list", params: { padding: padding } }.to_json)

    assert_response :content_too_large
  end

  test "an oversized body is caught even when Content-Length lies" do
    body = { jsonrpc: "2.0", id: 1, method: "tools/list", params: { padding: "x" * Rack::Attack::JSON_BODY_LIMIT } }.to_json
    post "/mcp", params: body, headers: { "CONTENT_TYPE" => "application/json", "CONTENT_LENGTH" => "100" }

    assert_equal 100, request.content_length
    assert_response :content_too_large
  end

  test "a body under the limit still reaches the controller intact" do
    post_mcp({ jsonrpc: "2.0", id: 7, method: "tools/list", params: { padding: "x" * 1000 } }.to_json)

    assert_response :success
    assert_equal 7, JSON.parse(response.body)["id"]
  end

  private

  def tools_list
    { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json
  end

  def post_mcp(body)
    post "/mcp", params: body, headers: { "CONTENT_TYPE" => "application/json" }
  end
end
