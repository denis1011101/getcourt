require "base64"
require "digest"
require "json"
require "openssl"
require "securerandom"
require "socket"

module Social
  module Nostr
    # Релеи говорят только по WebSocket, а гем ради одного текстового кадра в день
    # тянуть незачем: здесь ровно столько протокола, сколько нужно, чтобы
    # отправить ["EVENT", ...] и дождаться ["OK", id, ...].
    class Relay
      GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11".freeze

      class Error < StandardError; end

      def initialize(url, timeout: 10)
        @url = url
        @timeout = timeout
      end

      # true — релей подтвердил приём события.
      def publish(event)
        io = connect
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout

        io.write(Frame.encode(JSON.generate([ "EVENT", event.to_h ])))
        wait_for_ok(io, event.id, deadline)
      rescue => e
        Rails.logger.warn("[Social] nostr relay #{@url} failed: #{e.class} #{e.message}")
        false
      ensure
        close(io)
      end

      private

      def wait_for_ok(io, event_id, deadline)
        while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
          opcode, payload = Frame.read(io, deadline)
          return false if opcode.nil? || opcode == :close

          case opcode
          when :ping
            io.write(Frame.encode(payload, opcode: :pong))
          when :text
            message = JSON.parse(payload) rescue nil
            next unless message.is_a?(Array) && message[0] == "OK" && message[1] == event_id

            Rails.logger.warn("[Social] nostr relay #{@url} rejected: #{message[3]}") unless message[2]
            return !!message[2]
          end
        end

        false
      end

      def connect
        uri = URI(@url)
        raise Error, "unsupported scheme #{uri.scheme}" unless %w[ws wss].include?(uri.scheme)

        port = uri.port || (uri.scheme == "wss" ? 443 : 80)
        socket = Socket.tcp(uri.host, port, connect_timeout: @timeout)
        io = uri.scheme == "wss" ? wrap_tls(socket, uri.host) : socket
        handshake(io, uri)
        io
      end

      def wrap_tls(socket, hostname)
        context = OpenSSL::SSL::SSLContext.new
        context.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)
        ssl = OpenSSL::SSL::SSLSocket.new(socket, context)
        ssl.hostname = hostname
        ssl.sync_close = true
        ssl.connect
        ssl.post_connection_check(hostname)
        ssl
      end

      def handshake(io, uri)
        key = Base64.strict_encode64(SecureRandom.bytes(16))
        path = uri.path.presence || "/"
        path = "#{path}?#{uri.query}" if uri.query.present?

        io.write([
          "GET #{path} HTTP/1.1",
          "Host: #{uri.host}",
          "Upgrade: websocket",
          "Connection: Upgrade",
          "Sec-WebSocket-Key: #{key}",
          "Sec-WebSocket-Version: 13",
          "User-Agent: GetCourt",
          "", ""
        ].join("\r\n"))

        response = read_headers(io)
        raise Error, "handshake rejected: #{response.lines.first.to_s.strip}" unless response.start_with?("HTTP/1.1 101")

        expected = Base64.strict_encode64(Digest::SHA1.digest(key + GUID))
        raise Error, "bad Sec-WebSocket-Accept" unless response.match?(/^sec-websocket-accept:\s*#{Regexp.escape(expected)}\s*$/i)
      end

      def read_headers(io)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout
        buffer = +"".b

        until buffer.include?("\r\n\r\n")
          chunk = Frame.read_exactly(io, 1, deadline)
          raise Error, "connection closed during handshake" unless chunk

          buffer << chunk
        end

        buffer
      end

      def close(io)
        return unless io

        io.write(Frame.encode("", opcode: :close)) rescue nil
        io.close rescue nil
      end
    end
  end
end
