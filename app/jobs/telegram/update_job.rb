module Telegram
  class UpdateJob < ApplicationJob
    queue_as :default

    def perform(update)
      update = update.to_h if update.respond_to?(:to_h)

      Rails.logger.warn("[TG UPDATE] #{update.to_json}")

      if update.is_a?(Hash) && update["callback_query"].present?
        Telegram::CallbackHandler.handle(update["callback_query"])
        return
      end

      if update.is_a?(Hash) && update["message"].present?
        Telegram::MessageHandler.handle(update["message"])
        return
      end

      Rails.logger.info("[TG UPDATE] Unhandled keys=#{update.is_a?(Hash) ? update.keys : update.class}")
    end
  end
end
