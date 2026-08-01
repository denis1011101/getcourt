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

          # [bot-menu-off] Отключено намеренно: пользуемся сайтом getcourt.co,
          # бот оставлен только для приглашений и карточки игры.
          # Раскомментировать, если решим вернуть функциональность в бот.
          # begin
          #   return if Telegram::Flows::StatsScoreFlow.handle_message(message)
          # rescue => e
          #   Rails.logger.error "[Telegram::MainMenuProcessor] StatsScoreFlow error: #{e.class} #{e.message}"
          # end
          # begin
          #   return if Telegram::Flows::StatsFieldInputFlow.handle_message(message)
          # rescue => e
          #   Rails.logger.error "[Telegram::MainMenuProcessor] StatsFieldInputFlow error: #{e.class} #{e.message}"
          # end
          # chat = message["chat"] || {}
          # chat_id = (chat["id"] || message.dig("from", "id")).to_s
          # if Rails.cache.read("telegram:edit:chat:#{chat_id}")
          #   Telegram::Flows::Games::EditResponder.handle_message(message) rescue nil
          #   return
          # end
          # begin
          #   return if Telegram::Flows::Games::InviteFlow.handle_message(message)
          # rescue
          #   false
          # end
          # return if Telegram::Processors::ReplyProcessor.process(message)

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

            # [bot-menu-off] Отключено намеренно: пользуемся сайтом getcourt.co,
            # бот оставлен только для приглашений и карточки игры.
            # Раскомментировать, если решим вернуть функциональность в бот.
            # Telegram::Flows::ProfileFlow.start_onboarding(chat_id)
            Telegram::Handlers::MenuHandler.menu(chat_id) rescue nil
            nil

          when /\A\/register(?:@\w+)?\z/
            token = text.split(/\s+/, 2).last.to_s.strip
            user = token.present? ? User.find_by(telegram_registration_token: token) : nil

            if user
              User.transaction do
                User.where(telegram_chat_id: chat_id).where.not(id: user.id).update_all(telegram_chat_id: nil, updated_at: Time.current)
                user.update_columns(
                  telegram_chat_id: chat_id.to_s,
                  telegram_username: message.dig("from", "username").to_s.presence || user.telegram_username,
                  telegram_registration_token: nil,
                  updated_at: Time.current
                )
              end
              Telegram::Api.send_simple(chat_id, "Telegram connected to your GetCourt account.", parse_mode: nil)
              Telegram::Handlers::MenuHandler.menu(chat_id) rescue nil
            else
              Telegram::Api.send_simple(chat_id, "Registration code is invalid or expired. Please regenerate it in your account settings.", parse_mode: nil)
            end
            nil

            # [bot-menu-off] Отключено намеренно: пользуемся сайтом getcourt.co,
            # бот оставлен только для приглашений и карточки игры.
            # Раскомментировать, если решим вернуть функциональность в бот.
            # when "/menu"
            #   Telegram::Handlers::MenuHandler.menu(chat_id) rescue nil
            #   nil
          end
        rescue => e
          Rails.logger.error "[Telegram::MainMenuProcessor] handle_message error: #{e.class} #{e.message}\n#{e.backtrace.join("\n")}\nmessage: #{message.inspect}"
          raise
        end
      end
    end
  end
end
