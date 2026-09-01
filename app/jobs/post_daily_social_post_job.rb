# Один пост в день, каждый раз другой. Если материала нет — молчим: третий
# «⏱ 12 hours played» за неделю хуже пустого дня, в том числе для
# automated-labeling у модерации Bluesky.
class PostDailySocialPostJob < ApplicationJob
  queue_as :default

  def perform
    content = Social::DailyPlanner.new.pick

    if content.nil?
      Rails.logger.info("[Social] daily post skipped: no fresh material")
      return
    end

    Social.publish(content)
  end
end
