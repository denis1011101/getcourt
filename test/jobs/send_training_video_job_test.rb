require "test_helper"

class SendTrainingVideoJobTest < ActiveJob::TestCase
  setup do
    @game = games(:feed_upcoming)
    @approved = User.create!(email: "training-approved@example.com", locale: "en", notification_channel: "email")
    @pending = User.create!(email: "training-pending@example.com", locale: "en", notification_channel: "email")
    @game.participations.create!(user: @approved)
    @game.participations.create!(user: @pending, status: :pending)
    @game.participations.create!(guest_name: "Guest player")

    @medium = @game.game_media.new(user: @game.user)
    @medium.file.attach(
      io: StringIO.new("training video"),
      filename: "lesson.mp4",
      content_type: "video/mp4",
      identify: false
    )
    @medium.save!
  end

  test "delivers a GetCourt video link only to approved registered players" do
    deliveries = deliver_all

    assert_equal [ @approved.id ], deliveries.map { |delivery| delivery[:user].id }
    notification = deliveries.first[:notification]
    assert_equal "Training video for your game", notification.subject(:en)
    assert_equal "Watch video", notification.actions(:en).first[:label]
    assert_match %r{http://example.com/rails/active_storage/blobs/redirect/}, notification.actions(:en).first[:url]
  end

  test "names the person who uploaded the video instead of the organizer" do
    coach = User.create!(name: "Coach Marina", email: "training-coach@example.com")
    @medium.update!(user: coach)

    assert_equal "Coach Marina shared a training video with the players of your game.",
                 deliver_all.first[:notification].body(:en)
  end

  test "falls back to sender-neutral wording when the uploader has no name" do
    @medium.user.update_column(:name, nil)

    assert_equal "A training video has been shared with the players of your game.",
                 deliver_all.first[:notification].body(:en)
  end

  test "does not deliver a hidden video" do
    @medium.hide!

    assert_empty deliver_all
  end

  test "each approved player gets their own delivery job" do
    other = User.create!(email: "training-approved-2@example.com", locale: "en", notification_channel: "email")
    @game.participations.create!(user: other)

    # Раскладка по получателям: одна задача на игрока, чтобы падение доставки
    # не уносило с собой остальных.
    assert_enqueued_jobs 2, only: SendTrainingVideoJob do
      SendTrainingVideoJob.perform_now(@medium.id)
    end
  end

  test "a failed delivery is retried instead of being swallowed" do
    failing = ->(**_args) { raise "telegram is down" }

    assert_enqueued_with(job: SendTrainingVideoJob, args: [ @medium.id, @approved.id ]) do
      with_stubbed_singleton_method(NotificationDelivery, :deliver, failing) do
        SendTrainingVideoJob.perform_now(@medium.id, @approved.id)
      end
    end
  end

  private

  def deliver_all
    deliveries = []

    with_stubbed_singleton_method(NotificationDelivery, :deliver, ->(**args) { deliveries << args }) do
      perform_enqueued_jobs(only: SendTrainingVideoJob) { SendTrainingVideoJob.perform_now(@medium.id) }
    end

    deliveries
  end

  def with_stubbed_singleton_method(target, method_name, replacement)
    singleton = target.singleton_class
    original = singleton.instance_method(method_name)

    singleton.define_method(method_name) do |*args, **kwargs, &block|
      replacement.call(*args, **kwargs, &block)
    end

    yield
  ensure
    singleton.define_method(method_name, original)
  end
end
