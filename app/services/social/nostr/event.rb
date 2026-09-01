require "json"
require "openssl"

module Social
  module Nostr
    # NIP-01: id — sha256 от канонической сериализации, подпись — Schnorr по id.
    # Ruby-шный JSON.generate экранирует ровно то, что требует NIP-01 (кавычка,
    # обратный слэш, \n \r \t \b \f), а не-ASCII оставляет как есть.
    class Event
      attr_reader :kind, :content, :tags, :created_at

      def initialize(kind:, content:, secret_key:, tags: [], created_at: Time.now.to_i)
        @kind = kind
        @content = content.to_s
        @tags = tags
        @created_at = created_at.to_i
        @secret_key = secret_key
      end

      def pubkey
        @pubkey ||= Schnorr.public_key(@secret_key).unpack1("H*")
      end

      def id
        @id ||= OpenSSL::Digest::SHA256.hexdigest(serialized)
      end

      def signature
        @signature ||= Schnorr.sign([ id ].pack("H*"), @secret_key).unpack1("H*")
      end

      def to_h
        {
          "id" => id,
          "pubkey" => pubkey,
          "created_at" => created_at,
          "kind" => kind,
          "tags" => tags,
          "content" => content,
          "sig" => signature
        }
      end

      def serialized
        JSON.generate([ 0, pubkey, created_at, kind, tags, content ])
      end
    end
  end
end
