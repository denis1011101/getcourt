module Telegram
  module Helpers
    # Parses a raw Telegram callback_query hash into a simple struct.
    # Eliminates the duplicated 5-line preamble found in every handler/flow.
    #
    # Usage:
    #   cb = Telegram::Helpers::CallbackData.parse(callback_query)
    #   cb.data       # => "game:show:12:1"
    #   cb.cb_id      # => "abc123"
    #   cb.chat_id    # => "123456"  (always a String)
    #   cb.message_id # => 789  or nil
    #
    CallbackDataStruct = Struct.new(:data, :cb_id, :chat_id, :message_id, :from, keyword_init: true)

    module CallbackData
      def self.parse(callback_query)
        callback_query = callback_query.to_h if callback_query.respond_to?(:to_h) && !callback_query.is_a?(Hash)

        from = callback_query["from"] || {}

        CallbackDataStruct.new(
          data:       (callback_query["data"] || "").to_s,
          cb_id:      callback_query["id"],
          chat_id:    (callback_query.dig("message", "chat", "id") || from["id"]).to_s,
          message_id: callback_query.dig("message", "message_id") || callback_query["inline_message_id"],
          from:       from
        )
      end
    end
  end
end
