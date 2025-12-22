module Telegram
  class UpdateJob < ApplicationJob
    queue_as :default

    def perform(update)
      update = update.to_h if update.respond_to?(:to_h)
      Telegram::UpdateService.process(update)
    rescue => e
      Rails.logger.error("[Telegram::UpdateJob] #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}")
    end
  end
end
