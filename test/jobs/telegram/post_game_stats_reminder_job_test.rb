require "test_helper"
require "ostruct"

module Telegram
  class PostGameStatsReminderJobTest < ActiveJob::TestCase
    test "does nothing when game is missing" do
      Telegram::Api.stub(:send_with_buttons, ->(*) { flunk "should not send message" }) do
        PostGameStatsReminderJob.perform_now(-1)
      end
    end

    test "sends reminder with action buttons to game creator" do
      game = games(:one)
      game.user.update!(telegram_chat_id: 123_456)
      sent = nil

      Telegram::Api.stub(:send_with_buttons, ->(*args) { sent = args }) do
        PostGameStatsReminderJob.perform_now(game.id)
      end

      assert_equal 123_456, sent[0]
      assert_includes sent[1], "Please fill in the statistics via Telegram"
      assert_equal "Fill stats", sent[2][0][:text]
      assert_equal "tg_fill:#{game.id}", sent[2][0][:callback_data]
      assert_equal "Game did not happen", sent[2][1][:text]
      assert_includes sent[2][1][:url], "mark_not_happened="
    end

    test "recurring game reschedules next reminder and stores new job id" do
      game = games(:one)
      game.update!(
        recurring: true,
        date: Date.current + 7.days,
        time: "10:30",
        post_game_stats_reminder_job_id: "old-job-id"
      )
      game.user.update!(telegram_chat_id: 123_456)

      wait_until_seen = nil
      enqueued = OpenStruct.new(provider_job_id: "new-job-id")
      setter = Object.new
      setter.define_singleton_method(:perform_later) { |_game_id| enqueued }

      Telegram::PostGameStatsReminderJob.stub(:set, ->(wait_until:) { wait_until_seen = wait_until; setter }) do
        game.stub(:cancel_post_game_stats_reminder, true) do
          Telegram::Api.stub(:send_with_buttons, ->(*) {}) do
            PostGameStatsReminderJob.perform_now(game.id)
          end
        end
      end

      assert wait_until_seen.present?
      assert wait_until_seen > Time.current
      assert_equal "new-job-id", game.reload.post_game_stats_reminder_job_id
    end

    test "does not send reminder when creator has no telegram chat id" do
      game = games(:one)
      game.user.update!(telegram_chat_id: nil)

      Telegram::Api.stub(:send_with_buttons, ->(*) { flunk "should not send message" }) do
        PostGameStatsReminderJob.perform_now(game.id)
      end
    end
  end
end
