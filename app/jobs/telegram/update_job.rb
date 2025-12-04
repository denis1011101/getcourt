class Telegram::UpdateJob < ApplicationJob
  queue_as :default

  def perform(update)
    Telegram::UpdateService.process(update)
  end
end
