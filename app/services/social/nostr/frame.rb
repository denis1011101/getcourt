require "securerandom"

module Social
  module Nostr
    # Минимальный кодек кадров RFC 6455. Клиент обязан маскировать полезную
    # нагрузку, сервер — нет, поэтому чтение маску не разбирает.
    module Frame
      OPCODES = { continuation: 0x0, text: 0x1, binary: 0x2, close: 0x8, ping: 0x9, pong: 0xA }.freeze
      FIN = 0x80
      MASKED = 0x80

      class << self
        def encode(payload, opcode: :text)
          payload = payload.to_s.dup.force_encoding(Encoding::BINARY)
          length = payload.bytesize

          header = [ FIN | OPCODES.fetch(opcode) ].pack("C")
          header <<
            if length < 126
              [ MASKED | length ].pack("C")
            elsif length < 65_536
              [ MASKED | 126, length ].pack("Cn")
            else
              [ MASKED | 127, length ].pack("CQ>")
            end

          key = SecureRandom.bytes(4)
          header + key + mask(payload, key)
        end

        def mask(payload, key)
          payload.bytes.each_with_index.map { |byte, index| byte ^ key.getbyte(index % 4) }.pack("C*")
        end

        # Возвращает [опкод, payload] или nil, если соединение закрылось либо
        # истёк дедлайн.
        def read(io, deadline)
          header = read_exactly(io, 2, deadline)
          return nil unless header

          first, second = header.unpack("C2")
          length = second & 0x7F
          length = extended_length(io, length, deadline) if length >= 126
          return nil if length.nil?

          payload = length.zero? ? "".b : read_exactly(io, length, deadline)
          return nil if payload.nil?

          [ OPCODES.key(first & 0x0F), payload ]
        end

        def read_exactly(io, count, deadline)
          buffer = +"".b

          while buffer.bytesize < count
            chunk = read_some(io, count - buffer.bytesize, deadline)
            return nil unless chunk

            buffer << chunk
          end

          buffer
        end

        private

        def extended_length(io, marker, deadline)
          bytes = read_exactly(io, marker == 126 ? 2 : 8, deadline)
          return nil unless bytes

          marker == 126 ? bytes.unpack1("n") : bytes.unpack1("Q>")
        end

        def read_some(io, max, deadline)
          io.read_nonblock(max)
        rescue IO::WaitReadable
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          return nil if remaining <= 0
          return nil unless IO.select([ io.respond_to?(:to_io) ? io.to_io : io ], nil, nil, remaining)

          retry
        rescue EOFError, IOError, SystemCallError, OpenSSL::SSL::SSLError
          nil
        end
      end
    end
  end
end
