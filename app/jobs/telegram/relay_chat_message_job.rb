module Telegram
  # Разбор одного сообщения чата: кто его увидит. Сама отправка — в
  # DeliverChatMessageJob, по джобе на получателя.
  class RelayChatMessageJob < ApplicationJob
    queue_as :default

    def perform(game_id, sender_id, body)
      game = Game.find_by(id: game_id)
      sender = User.find_by(id: sender_id)
      return unless game && sender && body.present?

      # Отправитель тоже мог выйти из состава, пока сообщение ждало очереди.
      return unless game.chat_open? && game.team_member_ids.include?(sender.id)

      text = Telegram::Chat::Message.render(game: game, sender: sender, body: body)

      game.chat_members.where.not(id: sender.id).find_each do |recipient|
        Telegram::DeliverChatMessageJob.perform_later(game.id, recipient.id, text)
      end
    end
  end
end
