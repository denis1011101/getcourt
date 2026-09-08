require "test_helper"

class OutreachEmailJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  test "sends no more than the daily batch and remembers who got a letter" do
    12.times { |i| OutreachContact.create!(email: "club#{i}@example.org") }

    assert_emails OutreachContact::DAILY_BATCH do
      OutreachEmailJob.perform_now
    end

    assert_equal OutreachContact::DAILY_BATCH, OutreachContact.where.not(sent_at: nil).count
    assert_equal 2, OutreachContact.pending.count
  end

  test "a second run on the same day sends nothing" do
    12.times { |i| OutreachContact.create!(email: "club#{i}@example.org") }
    OutreachEmailJob.perform_now

    assert_no_emails do
      assert_equal 0, OutreachEmailJob.perform_now
    end

    assert_equal OutreachContact::DAILY_BATCH, OutreachContact.where.not(sent_at: nil).count
  end

  test "a bigger limit asked by hand is still cut down to the daily batch" do
    100.times { |i| OutreachContact.create!(email: "club#{i}@example.org") }

    assert_emails OutreachContact::DAILY_BATCH do
      OutreachEmailJob.perform_now(100)
    end
  end

  test "the next day continues where the previous one stopped" do
    12.times { |i| OutreachContact.create!(email: "club#{i}@example.org") }
    OutreachEmailJob.perform_now

    travel 1.day do
      assert_emails 2 do
        OutreachEmailJob.perform_now
      end
    end

    assert_equal [ "club10@example.org", "club11@example.org" ], ActionMailer::Base.deliveries.last(2).flat_map(&:to)
    assert_equal 0, OutreachContact.pending.count
  end

  test "skips contacts that unsubscribed" do
    OutreachContact.create!(email: "gone@example.org").unsubscribe
    OutreachContact.create!(email: "club@example.org")

    assert_emails 1 do
      OutreachEmailJob.perform_now
    end

    assert_equal [ "club@example.org" ], ActionMailer::Base.deliveries.last.to
  end

  test "an outage of the mail service does not eat the list, however long it lasts" do
    3.times { |i| OutreachContact.create!(email: "club#{i}@example.org") }

    OutreachContact::MAX_ATTEMPTS.times do
      assert_raises(Net::SMTPServerBusy) do
        with_mail_service_down { OutreachEmailJob.perform_now }
      end
    end

    assert_equal 3, OutreachContact.pending.count
    assert_equal [ 0, 0, 0 ], OutreachContact.order(:id).pluck(:attempts)
    assert_match "421 service unavailable", OutreachContact.first.last_error
  end

  test "an outage frees the whole batch right away, without waiting out the reservation" do
    3.times { |i| OutreachContact.create!(email: "club#{i}@example.org") }

    assert_raises(Net::SMTPServerBusy) do
      with_mail_service_down { OutreachEmailJob.perform_now }
    end

    assert_empty OutreachContact.where.not(reserved_at: nil)
  end

  test "a rejected address is retried later and does not stop the batch" do
    OutreachContact.create!(email: "bad@example.org")
    good = OutreachContact.create!(email: "club@example.org")

    with_rejecting_delivery do
      OutreachEmailJob.perform_now
    end

    bad = OutreachContact.find_by(email: "bad@example.org")
    assert_nil bad.sent_at
    assert_nil bad.reserved_at
    assert_equal 1, bad.attempts
    assert_match "550 mailbox unavailable", bad.last_error
    assert_not_nil good.reload.sent_at
  end

  test "gives up on an address after MAX_ATTEMPTS" do
    contact = OutreachContact.create!(email: "bad@example.org")

    with_rejecting_delivery do
      OutreachContact::MAX_ATTEMPTS.times { OutreachEmailJob.perform_now }
    end

    assert_equal OutreachContact::MAX_ATTEMPTS, contact.reload.attempts
    assert_empty OutreachContact.pending
  end

  test "a run that overlaps with another one picks nobody twice" do
    3.times { |i| OutreachContact.create!(email: "club#{i}@example.org") }
    in_flight = OutreachContact.pending.limit(2).to_a
    in_flight.each { |contact| contact.update!(reserved_at: Time.current) }

    assert_emails 1 do
      OutreachEmailJob.perform_now
    end

    assert_equal [ "club2@example.org" ], ActionMailer::Base.deliveries.last.to
    assert_equal [ nil, nil ], in_flight.map { |contact| contact.reload.sent_at }
  end

  test "a batch left hanging by a crashed run is retried once its reservation goes stale" do
    12.times { |i| OutreachContact.create!(email: "club#{i}@example.org") }
    crashed_run_reserves OutreachContact::DAILY_BATCH

    travel OutreachContact::RESERVATION_TTL + 1.minute do
      assert_emails OutreachContact::DAILY_BATCH do
        OutreachEmailJob.perform_now
      end
    end
  end

  test "a batch reserved before midnight still holds the limit after it" do
    12.times { |i| OutreachContact.create!(email: "club#{i}@example.org") }
    travel_to(Time.zone.parse("2026-09-09 23:59")) { crashed_run_reserves OutreachContact::DAILY_BATCH }

    travel_to Time.zone.parse("2026-09-10 00:01") do
      assert_no_emails do
        assert_equal 0, OutreachEmailJob.perform_now
      end
    end
  end

  private
    # Почта, где адрес bad@example.org отбивается навсегда, — так отвечает Resend,
    # когда ящика на той стороне нет.
    class RejectingDelivery
      def initialize(settings = {}); end

      def deliver!(mail)
        raise Net::SMTPFatalError, "550 mailbox unavailable" if mail.to.include?("bad@example.org")

        ActionMailer::Base.deliveries << mail
      end
    end

    # Почта, которая не принимает вообще ничего: авария на стороне сервиса, а не
    # отказ конкретного ящика.
    class UnavailableDelivery
      def initialize(settings = {}); end

      def deliver!(_mail)
        raise Net::SMTPServerBusy, "421 service unavailable"
      end
    end

    # Запуск, который забрал адреса и умер, не успев отправить письма.
    def crashed_run_reserves(count)
      OutreachContact.pending.limit(count).each { |contact| contact.update!(reserved_at: Time.current) }
    end

    def with_rejecting_delivery(&block)
      with_delivery_method(:rejecting, RejectingDelivery, &block)
    end

    def with_mail_service_down(&block)
      with_delivery_method(:unavailable, UnavailableDelivery, &block)
    end

    def with_delivery_method(name, implementation)
      ActionMailer::Base.add_delivery_method name, implementation
      previous = ActionMailer::Base.delivery_method
      ActionMailer::Base.delivery_method = name
      yield
    ensure
      ActionMailer::Base.delivery_method = previous
    end
end
