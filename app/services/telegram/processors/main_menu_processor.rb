module Telegram
  module Processors
    class MainMenuProcessor
      class << self
        # Process only top-level main-menu updates (currently only /courts command)
        def process_update(update)
          if (msg = update["message"])
            handle_message(msg)
          end
        rescue => e
          Rails.logger.error "[Telegram::MainMenuProcessor] process_update error: #{e.class} #{e.message}"
        end

        def handle_message(message)
          Rails.logger.debug "[Telegram::MainMenuProcessor] incoming message: #{message.inspect}"

          # 0) Score input (ожидаем счёт) — перехватываем первым
          begin
            return if Telegram::Flows::StatsScoreFlow.handle_message(message)
          rescue => e
            Rails.logger.error "[Telegram::MainMenuProcessor] StatsScoreFlow error: #{e.class} #{e.message}"
          end

          # 1) Stats field input (ожидаем число) — перехватываем первым
          begin
            return if Telegram::Flows::StatsFieldInputFlow.handle_message(message)
          rescue => e
            Rails.logger.error "[Telegram::MainMenuProcessor] StatsFieldInputFlow error: #{e.class} #{e.message}"
          end

          # route ordinary messages to edit flow responder if edit in progress for this chat
          chat = message["chat"] || {}
          chat_id = (chat["id"] || message.dig("from", "id")).to_s
          if Rails.cache.read("telegram:edit:chat:#{chat_id}")
            Telegram::Flows::Games::EditResponder.handle_message(message) rescue nil
            return
          end

          # Wrap the entire if statement in a begin-rescue block
          begin
            if Telegram::Flows::Games::InviteFlow.handle_message(message)
              return
            end
          rescue
            false
          end

          # handle replies to ForceReply prompts globally
          return if Telegram::Processors::ReplyProcessor.process(message)


          chat = message["chat"] || {}
          chat_id = (chat["id"] || message.dig("from", "id")).to_s
          text = message["text"].to_s.strip
          cmd = text.split.first.to_s.downcase

          case cmd
          when /\A\/start\b/
            chat_id = message.dig("chat", "id") || message.dig("from", "id")
            begin
              user = User.find_or_initialize_by(telegram_chat_id: chat_id.to_s)
              if user.new_record?
                user.telegram_username = message.dig("from", "username") rescue nil
                user.name = message.dig("from", "first_name") rescue nil if user.respond_to?(:name=)
                user.save(validate: false) rescue nil
                Rails.logger.info "[Telegram::MainMenuProcessor] created user id=#{user.id} chat=#{chat_id}"
              end
            rescue => e
              Rails.logger.error "[Telegram::MainMenuProcessor] user create error: #{e.class} #{e.message}"
            end

            if defined?(Telegram::Flows::ProfileFlow) && Telegram::Flows::ProfileFlow.respond_to?(:start_onboarding)
              Telegram::Flows::ProfileFlow.start_onboarding(chat_id)
            else
              Telegram::Handlers::MenuHandler.menu(chat_id) rescue nil
            end
            nil

          when "/menu"
            Telegram::Handlers::MenuHandler.menu(chat_id) rescue nil
            nil
          end
        rescue => e
          Rails.logger.error "[Telegram::MainMenuProcessor] handle_message error: #{e.class} #{e.message}\n#{e.backtrace.join("\n")}\nmessage: #{message.inspect}"
          raise
        end
      end
    end
  end
end
