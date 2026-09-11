require "test_helper"
require "ostruct"

class PostGameStatsReminderJobTest < ActiveJob::TestCase
    include ActionMailer::TestHelper

    test "does nothing when game is missing" do
      with_stubbed_singleton_method(Telegram::Api, :send_with_buttons, ->(*) { flunk "should not send message" }) do
        PostGameStatsReminderJob.perform_now(-1)
      end
      assert_nil Game.find_by(id: -1)
    end

    test "sends reminder with action buttons to game creator" do
      game = games(:one)
      game.user.update_columns(telegram_chat_id: 123_456, telegram_locale: "en", notification_channel: "telegram")
      sent = nil

      with_stubbed_singleton_method(Telegram::Api, :send_with_buttons, ->(*args) { sent = args }) do
        PostGameStatsReminderJob.perform_now(game.id)
      end

      assert_equal 123_456, sent[0]
      assert_includes sent[1], "Please fill in the statistics on GetCourt"
      assert_equal "Fill stats", sent[2][0][0][:text]
      assert_equal "http://localhost:3000/games/#{game.id}", sent[2][0][0][:url]
      assert sent[2].flatten.none? { |button| button.key?(:callback_data) }
      assert_equal "Game did not happen", sent[2][1][0][:text]
      assert_includes sent[2][1][0][:url], "mark_not_happened="
    end

    test "recurring game reschedules next reminder and stores new job id" do
      game = games(:one)
      game.update!(
        recurring: true,
        date: Date.current + 7.days,
        time: "10:30",
        post_game_stats_reminder_job_id: "old-job-id"
      )
      game.user.update_columns(telegram_chat_id: 123_456, notification_channel: "telegram")

      wait_until_seen = nil
      enqueued = OpenStruct.new(provider_job_id: "new-job-id")
      setter = Object.new
      setter.define_singleton_method(:perform_later) { |_game_id| enqueued }

      with_stubbed_singleton_method(PostGameStatsReminderJob, :set, ->(wait_until:) { wait_until_seen = wait_until; setter }) do
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

    # Серия «пн + чт»: после понедельника напоминание должно ждать четверга, а
    # не следующего понедельника — шаг в неделю проскакивал занятие.
    test "the next reminder lands on the next session of the schedule" do
      game = Game.create!(
        court: courts(:one), user: users(:one), time: "18:00",
        date: Date.new(2026, 9, 7), occurrence_dates: %w[2026-09-07 2026-09-10]
      )

      travel_to Time.zone.local(2026, 9, 7, 22, 0) do
        reminder_at = PostGameStatsReminderJob.new.send(:next_recurring_reminder_at, game)

        assert_equal game.occurrence_starts_at(Date.new(2026, 9, 10)) + 4.hours, reminder_at
      end
    end

    # У занятия в 22:00 напоминание приходится на два часа ночи следующих
    # суток: сегодняшний вечер к этому моменту ещё впереди, и вычёркивать
    # сегодняшний день целиком нельзя.
    test "a reminder that fires after midnight still sees today's session" do
      game = Game.create!(
        court: courts(:one), user: users(:one), time: "22:00",
        date: Date.new(2026, 9, 7), occurrence_dates: %w[2026-09-07 2026-09-08]
      )

      travel_to game.occurrence_starts_at(Date.new(2026, 9, 7)) + 4.hours do
        reminder_at = PostGameStatsReminderJob.new.send(:next_recurring_reminder_at, game)

        assert_equal game.occurrence_starts_at(Date.new(2026, 9, 8)) + 4.hours, reminder_at
      end
    end

    # Расписание кончилось — напоминать больше не о чем.
    test "a finished schedule gets no further reminder" do
      game = Game.create!(
        court: courts(:one), user: users(:one), time: "18:00",
        date: Date.new(2026, 9, 7), occurrence_dates: %w[2026-09-07 2026-09-10]
      )

      travel_to Time.zone.local(2026, 9, 10, 22, 0) do
        assert_nil PostGameStatsReminderJob.new.send(:next_recurring_reminder_at, game)
      end
    end

    test "does not send reminder when creator has no telegram chat id" do
      game = games(:one)
      game.user.update_columns(telegram_chat_id: nil, notification_channel: "telegram")

      with_stubbed_singleton_method(Telegram::Api, :send_with_buttons, ->(*) { flunk "should not send message" }) do
        PostGameStatsReminderJob.perform_now(game.id)
      end
      assert_nil game.user.reload.telegram_chat_id
    end

    test "sends reminder by email when email is selected" do
      game = games(:one)
      game.user.update_columns(email: "stats-reminder@example.com", locale: "en", notification_channel: "email")

      assert_enqueued_emails 1 do
        with_stubbed_singleton_method(Telegram::Api, :send_with_buttons, ->(*) { flunk "should not send telegram message" }) do
          PostGameStatsReminderJob.perform_now(game.id)
        end
      end
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
