module Telegram
  module Handlers
    class StartHandler
      class << self
        # Handle incoming /start message (message is the Telegram message hash)
        def handle(message)
          chat = message["chat"] || {}
          chat_id = (chat["id"] || "").to_s
          return unless chat_id.present?

          user = nil
          created = false
          begin
            user, created = Telegram::UserService.find_or_create_for_chat(chat)
          rescue => e
            Rails.logger.error "[Telegram::Handlers::StartHandler] user lookup error: #{e.class} #{e.message}"
          end

          if !created
            Telegram::Handlers::MenuHandler.menu(chat_id)
          else
            SurveyHandler.start(chat_id, user)
          end
        end
      end
    end
  end
end
