module Telegram
  module Chat
    # Чат закрывается не действием человека, а расписанием: в ночь на субботу
    # состав сбрасывают, а прошедшую разовую игру удаляют совсем. Без письма
    # человек узнал бы об этом, только когда его сообщение перестало доходить
    # до команды, — а оно просто не уходит, молча.
    module Closure
      Notice = Struct.new(:user, :text)

      class << self
        # Текст собираем до того, как игру снесут: после удаления ни состава, ни
        # ярлыка с городом и датой уже не собрать.
        def prepare(game, reason, users = nil)
          return [] if game.nil?

          (users || game.chat_members).to_a.filter_map do |user|
            next if user.nil? || user.telegram_chat_id.blank?

            locale = Telegram::I18n.locale_for(user)
            Notice.new(user, Telegram::I18n.t(
              reason, locale: locale, game: Message.game_label(game, locale: locale)
            ))
          end
        end

        # Указатель гасим здесь же: иначе человек останется в чате, которого уже
        # нет, и следующее его сообщение уйдёт в никуда.
        def deliver(game, notices)
          notices.each do |notice|
            Session.stop_for(notice.user, game)
            SendTelegramNotificationJob.perform_later(notice.user.telegram_chat_id.to_s, notice.text)
          end
          notices.size
        end

        def notify(game, reason, users = nil)
          deliver(game, prepare(game, reason, users))
        end
      end
    end
  end
end
