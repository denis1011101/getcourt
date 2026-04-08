module Telegram
  module Flows
    class GamesFlow
      class << self
        def handle_callback(callback)
          cb = Telegram::Helpers::CallbackData.parse(callback)
          Rails.logger.debug "[Telegram::Flows::GamesFlow] enter handle_callback data=#{cb.data.inspect}"
          poller = Telegram::Poller.new

          return true if Telegram::Flows::Games::InviteFlow.handle_callback(callback) rescue false
          return true if Telegram::Flows::Games::ParticipantsManageFlow.handle_callback(callback) rescue false

          case cb.data
          when /\Agame:show:(\d+):(\d+)\z/
            gid = $1.to_i
            page = $2.to_i
            poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil
            begin
              Telegram::Handlers::GamesHandler.show_game(cb.chat_id, gid, page, message_id: cb.message_id)
            rescue => e
               Rails.logger.error "[Telegram::Flows::GamesFlow] show_game error: #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}"
               raise
            end
            nil

          when /\Agame:players:(\d+):(\d+)\z/
            gid = $1.to_i
            page = $2.to_i
            poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil
            Telegram::Handlers::GamesHandler.show_players(cb.chat_id, gid, page, message_id: cb.message_id) rescue nil
            nil

          when /\Agame:share:(\d+):(\d+)\z/
            gid = $1.to_i
            begin
              poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil
              locale = Telegram::Helpers::UserLookup.locale_for(cb.chat_id)
              game = Game.includes(:court, :participations).find_by(id: gid)
              return Telegram::Api.send_simple(cb.chat_id, Telegram::I18n.t(:game_not_found, locale: locale)) unless game

              path = Telegram::Helpers::GameCardRenderer.render(game, locale: locale)

              host = ENV.fetch("APP_HOST", "https://getcourt.co")
              game_url = Rails.application.routes.url_helpers.game_url(game, host: host)
              owner_user = User.find_by(id: game.user_id)
              owner_name = Telegram::Helpers::UserLookup.display_name(owner_user, fallback: owner_user&.telegram_chat_id || "—")
              owner_tg = owner_user&.telegram_username.to_s.strip.delete_prefix("@")
              owner_link = owner_tg.present? ? "https://t.me/#{owner_tg}" : owner_name

              caption = Telegram::I18n.t(:share_game_caption, locale: locale, id: game.id, game_url: game_url, owner_url: owner_link)
              Telegram::Api.send_photo(cb.chat_id, path, caption: caption)
              nil
            rescue => e
              Rails.logger.error "[Telegram::Flows::GamesFlow] share_game error: #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}"
              Telegram::Api.send_simple(cb.chat_id, Telegram::I18n.t(:share_game_failed, locale: locale), parse_mode: nil) rescue nil
              nil
            ensure
              File.delete(path) if path.present? && File.exist?(path)
            end

          when /\Agame:invite:/, /\Agame:invite_decline:/
            handled = Telegram::Flows::Games::InviteFlow.handle_callback(callback) rescue false
            handled

          when /\Agame:prebook/, /\Aprebook:/
            Rails.logger.debug "[Telegram::Flows::GamesFlow] delegating to Games::PrebookFlow data=#{cb.data.inspect}"
            begin
              result = Telegram::Flows::Games::PrebookFlow.handle_callback(callback)
              Rails.logger.debug "[Telegram::Flows::GamesFlow] Games::PrebookFlow returned=#{result.inspect}"
            rescue => e
              Rails.logger.error "[Telegram::Flows::GamesFlow] prebook flow error: #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}"
              result = nil
            end
            result

          when /\Agame:/
            Telegram::Flows::Games::ManageFlow.handle_callback(callback) rescue nil
            nil

          else
            # other actions handled elsewhere
          end
        rescue => e
          Rails.logger.error "[Telegram::Flows::Games::ManageFlow] callback error: #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
          nil
        end
      end
    end
  end
end
