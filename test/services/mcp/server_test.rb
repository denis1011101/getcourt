require "test_helper"

class Mcp::ServerTest < ActiveSupport::TestCase
  setup do
    @server = Mcp::Server.new(host: "https://getcourt.co")
  end

  test "negotiates the protocol version the client asked for" do
    result = call("initialize", params: { "protocolVersion" => "2024-11-05" })[:result]

    assert_equal "2024-11-05", result[:protocolVersion]
    assert_equal "getcourt", result[:serverInfo][:name]

    # Незнакомую версию не повторяем — предлагаем свою последнюю.
    unknown = call("initialize", params: { "protocolVersion" => "1999-01-01" })[:result]
    assert_equal Mcp::Server::LATEST_PROTOCOL, unknown[:protocolVersion]
  end

  test "stays silent on notifications" do
    assert_nil @server.call({ "jsonrpc" => "2.0", "method" => "notifications/initialized" })
  end

  test "lists only read-only tools" do
    tools = call("tools/list")[:result][:tools]

    assert_equal %w[search_games get_game], tools.map { |tool| tool[:name] }
  end

  test "search_games returns upcoming games on approved courts" do
    games = tool_payload("search_games", {})["games"]
    ids = games.map { |game| game["id"] }

    assert_includes ids, games(:feed_upcoming).id
    assert_not_includes ids, games(:one).id
  end

  test "search_games honours filters" do
    urgent = tool_payload("search_games", { "urgent" => true })["games"]

    assert_equal [ games(:feed_urgent).id ], urgent.map { |game| game["id"] }
    assert_empty tool_payload("search_games", { "sport" => "curling" })["games"]
  end

  test "get_game reports a missing game as invalid params rather than crashing" do
    found = tool_payload("get_game", { "id" => games(:feed_upcoming).id })

    assert_equal games(:feed_upcoming).id, found["game"]["id"]

    error = call("tools/call", params: { "name" => "get_game", "arguments" => { "id" => -1 } })[:error]
    assert_equal Mcp::Server::INVALID_PARAMS, error[:code]
  end

  test "get_game refuses a game whose court is still in moderation" do
    error = call("tools/call", params: { "name" => "get_game", "arguments" => { "id" => games(:one).id } })[:error]

    assert_equal Mcp::Server::INVALID_PARAMS, error[:code]
  end

  test "answers unknown methods and tools with proper JSON-RPC errors" do
    assert_equal Mcp::Server::METHOD_NOT_FOUND, call("resources/list")[:error][:code]

    unknown_tool = call("tools/call", params: { "name" => "delete_everything" })[:error]
    assert_equal Mcp::Server::INVALID_PARAMS, unknown_tool[:code]
  end

  test "rejects a payload that is not a JSON-RPC object" do
    assert_equal Mcp::Server::INVALID_REQUEST, @server.call("hello")[:error][:code]
  end

  private

  def call(method, params: {}, id: 1)
    @server.call({ "jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params })
  end

  def tool_payload(name, arguments)
    response = call("tools/call", params: { "name" => name, "arguments" => arguments })

    JSON.parse(response[:result][:content].first[:text])
  end
end
