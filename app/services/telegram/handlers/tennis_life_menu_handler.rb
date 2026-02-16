module Telegram
  module Handlers
    class TennisLifeMenuHandler
      class << self
        include Telegram::Handlers::ReplyHelpers

        def show(chat_id, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          # Show recent posts from tracked Telegram channels
          posts = fetch_recent_posts(limit: 5)

          lines = [ "*#{t.(:tennis_life_title)}*", "" ]

          if posts.any?
            posts.each do |post|
              channel = post.telegram_channel
              preview = post.text.to_s.strip.truncate(120)
              date = post.published_at&.strftime("%d.%m.%Y") || "—"
              lines << "#{date} — @#{channel.username}"
              lines << preview
              lines << ""
            end
          else
            lines << t.(:tennis_life_text)
          end

          text = lines.join("\n")
          buttons = [ [ { text: t.(:main_menu_btn), callback_data: "menu:main" } ] ]

          send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
        end

        private

        def fetch_recent_posts(limit: 5)
          if defined?(TelegramPost)
            TelegramPost.includes(:telegram_channel)
                        .order(published_at: :desc)
                        .limit(limit)
                        .to_a
          else
            []
          end
        rescue => e
          Rails.logger.error "[TennisLifeMenuHandler] #{e.class}: #{e.message}"
          []
        end
      end
    end
  end
end
