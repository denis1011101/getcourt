require "test_helper"
require "ostruct"

module Telegram
  class PostGameStatsReminderJobTest < ActiveJob::TestCase
    test "does nothing when game is missing" do
      with_stubbed_singleton_method(Telegram::Api, :send_with_buttons, ->(*) { flunk "should not send message" }) do
        PostGameStatsReminderJob.perform_now(-1)
      end
      assert_nil Game.find_by(id: -1)
    end

    test "sends reminder with action buttons to game creator" do
      game = games(:one)
      game.user.update_column(:telegram_chat_id, 123_456)
      sent = nil

      with_stubbed_singleton_method(Telegram::Api, :send_with_buttons, ->(*args) { sent = args }) do
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
      game.user.update_column(:telegram_chat_id, 123_456)

      wait_until_seen = nil
      enqueued = OpenStruct.new(provider_job_id: "new-job-id")
      setter = Object.new
      setter.define_singleton_method(:perform_later) { |_game_id| enqueued }

      with_stubbed_singleton_method(Telegram::PostGameStatsReminderJob, :set, ->(wait_until:) { wait_until_seen = wait_until; setter }) do
        with_stubbed_singleton_method(game, :cancel_post_game_stats_reminder, true) do
          with_stubbed_singleton_method(Telegram::Api, :send_with_buttons, ->(*) { }) do
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
      game.user.update_column(:telegram_chat_id, nil)

      with_stubbed_singleton_method(Telegram::Api, :send_with_buttons, ->(*) { flunk "should not send message" }) do
        PostGameStatsReminderJob.perform_now(game.id)
      end
      assert_nil game.user.reload.telegram_chat_id
    end

    private

    def with_stubbed_singleton_method(target, method_name, replacement)
      singleton = target.singleton_class
      had_method = singleton.method_defined?(method_name) || singleton.private_method_defined?(method_name)
      original = singleton.instance_method(method_name) if had_method
      callable = replacement.respond_to?(:call) ? replacement : ->(*) { replacement }

      singleton.define_method(method_name) do |*args, **kwargs, &block|
        callable.call(*args, **kwargs, &block)
      end

      yield
    ensure
      if had_method
        singleton.define_method(method_name, original)
      else
        singleton.remove_method(method_name)
      end
    end
  end
end
