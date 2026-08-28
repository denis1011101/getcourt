module Telegram
  module Flows
    module Games
      # Голосование за правку плана тренировки: кнопки «за» и «против» под
      # сообщением бота — единственное, что нужно от участника.
      module PlanVoteFlow
        PATTERN = /\Agame:plan_vote:(\d+):(yes|no)\z/

        class << self
          def handle_callback(callback)
            match = PATTERN.match((callback["data"] || "").to_s)
            return false unless match

            chat_id = (callback.dig("message", "chat", "id") || callback.dig("from", "id")).to_s
            locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
            proposal = TrainingPlanProposal.find_by(id: match[1].to_i)
            voter = Telegram::Helpers::UserLookup.find_user(chat_id)

            Telegram::Api.answer_callback(callback["id"], answer_for(proposal, voter, match[2] == "yes", locale)) rescue nil
            # Бюллетень отработал — кнопки под сообщением больше ни к чему.
            drop_buttons(callback)
            true
          rescue => e
            Rails.logger.error "[Telegram::Flows::Games::PlanVoteFlow] callback error: #{e.class}: #{e.message}"
            false
          end

          private

          def answer_for(proposal, voter, in_favor, locale)
            return Telegram::I18n.t(:plan_vote_closed, locale: locale) if proposal.nil? || !proposal.voting?
            return Telegram::I18n.t(:plan_vote_not_allowed, locale: locale) unless proposal.vote!(voter, in_favor)

            TrainingPlanProposalNotifier.settled(proposal) unless proposal.open?
            Telegram::I18n.t(:plan_vote_counted, locale: locale)
          end

          def drop_buttons(callback)
            chat_id = callback.dig("message", "chat", "id")
            message_id = callback.dig("message", "message_id")
            return if chat_id.blank? || message_id.blank?

            Telegram::Api.send_api("editMessageReplyMarkup", {
              chat_id: chat_id,
              message_id: message_id,
              reply_markup: { inline_keyboard: [] }
            })
          rescue => e
            Rails.logger.warn "[Telegram::Flows::Games::PlanVoteFlow] keyboard cleanup failed: #{e.class}: #{e.message}"
          end
        end
      end
    end
  end
end
