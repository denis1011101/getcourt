module Telegram
  # Вложение из чата попадает и на страницу игры. Качаем файл один раз здесь, а
  # не в каждой доставке: получателям он уходит по file_id, без нашего диска.
  #
  # Витрину Tennis Life джоба не трогает: show_in_feed остаётся выключенным,
  # вынести вложение туда — отдельное решение автора на сайте.
  class AttachChatMediaJob < ApplicationJob
    queue_as :default

    # Потолок скачивания у Bot API — 20 МБ, и он ниже нашего лимита на видео.
    # Проверяем до getFile: размер Telegram сообщает прямо в сообщении.
    MAX_DOWNLOAD = 20.megabytes

    def perform(game_id, user_id, media, caption = nil)
      game = Game.find_by(id: game_id)
      user = User.find_by(id: user_id)
      return unless game && user && Telegram::Chat::Media.attachable?(media)

      # Прикладывают к игре только те, кто в составе, — как и на сайте.
      return unless game.chat_open? && game.team_member_ids.include?(user.id)

      locale = Telegram::I18n.locale_for(user)
      return reply(user, :chat_media_too_big, locale) if media["file_size"].to_i > MAX_DOWNLOAD

      file, filename = Telegram::Api.download_file(media["file_id"])
      return reply(user, :chat_media_download_failed, locale) unless file

      begin
        attach(game, user, file, filename, caption, locale)
      ensure
        file.close
        file.unlink
      end
    end

    private

    def attach(game, user, file, filename, caption, locale)
      medium = game.game_media.new(user: user, title: title_from(caption))
      medium.file.attach(io: file, filename: filename)

      # Сообщения валидаций отдаёт Rails, и они должны быть на языке человека.
      ::I18n.with_locale(locale) do
        if medium.save
          reply(user, :chat_media_saved, locale)
        else
          # Блоб уже лежит на диске: без явной чистки несохранённое вложение
          # осталось бы там навсегда.
          medium.file.purge
          reply(user, :chat_media_failed, locale, reason: medium.errors.full_messages.to_sentence)
        end
      end
    end

    def title_from(caption)
      caption.to_s.strip.presence&.truncate(GameMedium::MAX_TITLE_LENGTH)
    end

    def reply(user, key, locale, **args)
      Telegram::Api.send_simple(
        user.telegram_chat_id, Telegram::I18n.t(key, locale: locale, **args), parse_mode: nil
      )
      nil
    end
  end
end
