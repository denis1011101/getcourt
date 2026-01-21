require 'tdlib-ruby'
require 'json'
require 'net/http'
require 'uri'

TD.configure do |cfg|
  cfg.lib_path = ENV.fetch("TDLIB_LIB_PATH", Rails&.root&.join("vendor")&.to_s || "./vendor")
  cfg.client.api_id   = ENV.fetch("TELEGRAM_API_ID")
  cfg.client.api_hash = ENV.fetch("TELEGRAM_API_HASH")
  cfg.client.system_language_code = "en"
  cfg.client.database_directory = ENV.fetch("TDLIB_DB_DIR", "./.tdlib_db")
end

client = TD::Client.new
client.connect

# simple auth flow for interactive run (only first time)
state = nil
client.on(TD::Types::Update::AuthorizationState) do |u|
  state = u.authorization_state
end

# wait for state to settle and perform interactive auth if needed
start = Time.now
loop do
  break if state && state.is_a?(TD::Types::AuthorizationState::Ready)
  case state
  when TD::Types::AuthorizationState::WaitPhoneNumber
    print "Phone: "
    client.set_authentication_phone_number(phone_number: STDIN.gets.strip, settings: nil).wait
  when TD::Types::AuthorizationState::WaitCode
    print "Code: "
    client.check_authentication_code(code: STDIN.gets.strip).wait
  when TD::Types::AuthorizationState::WaitPassword
    print "2FA password: "
    client.check_authentication_password(password: STDIN.gets.strip).wait
  end
  sleep 0.1
  # simple timeout to avoid endless loop in non-interactive mode
  raise "Auth timeout" if Time.now - start > 60 && !ENV['NON_INTERACTIVE']
end

channels = (ENV["TELEGRAM_CHANNELS"] || "").split(",").map { |s| s.strip.sub(/^@/, '') }
rails_url = ENV.fetch("RAILS_API_URL", "http://127.0.0.1:3000")
rails_token = ENV["RAILS_API_TOKEN"]

channels.each do |username|
  begin
    chat = client.get_chat(chat_id: username) rescue nil
    # fallback: resolve by username
    if chat.nil?
      user = client.search_public_chat(username) rescue nil
      chat = user if user
    end
    next unless chat
    chat_id = chat.id

    # get history (last 200)
    history = client.get_chat_history(chat_id: chat_id, limit: 200) rescue []
    messages = (history.is_a?(Array) ? history : [history]).map do |m|
      {
        message_id: m.id,
        date: m.date,
        text: (m.message || (m.caption if m.respond_to?(:caption))),
        raw: m.to_h rescue {}
      }
    end

    # send to rails api
    uri = URI("#{rails_url}/api/telegram_posts")
    messages.each do |msg|
      req = Net::HTTP::Post.new(uri)
      req['Content-Type'] = 'application/json'
      req['X-API-TOKEN'] = rails_token if rails_token
      req.body = {
        channel_username: username,
        message_id: msg[:message_id],
        date: msg[:date],
        text: msg[:text],
        raw: msg[:raw]
      }.to_json
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(req)
      end
    end
  rescue => e
    warn "fetch #{username} failed: #{e.class} #{e.message}"
  end
end

client.dispose
