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
    assert_equal "New video in your game", notification.subject(:en)
    assert_equal "Watch video", notification.actions(:en).first[:label]
    assert_match %r{http://example.com/rails/active_storage/blobs/redirect/}, notification.actions(:en).first[:url]
  end

  test "names the person who uploaded the video instead of the organizer" do
    coach = User.create!(name: "Coach Marina", email: "training-coach@example.com")
    @medium.update!(user: coach)

    assert_equal "Coach Marina shared a video.", deliver_all.first[:notification].body(:en)
  end

  test "the telegram handle goes next to the name, the email never does" do
    coach = User.create!(name: "Coach Marina", email: "training-coach-tg@example.com", telegram_username: "@marina_tg")
    @medium.update!(user: coach)

    body = deliver_all.first[:notification].body(:en)

    assert_equal "Coach Marina (@marina_tg) shared a video.", body
    assert_not_includes body, coach.email
  end

  test "the handle alone stands in for a player with no name" do
    author = User.create!(email: "training-nameless@example.com", telegram_username: "nameless_one")
    @medium.update!(user: author)

    assert_equal "@nameless_one shared a video.", deliver_all.first[:notification].body(:en)
  end

  test "the title the uploader typed goes into the message" do
    coach = User.create!(name: "Coach Marina", email: "training-titled@example.com")
    @medium.update!(user: coach, title: "Serve breakdown")

    assert_equal "Coach Marina shared the video \u201CServe breakdown\u201D.",
                 deliver_all.first[:notification].body(:en)
  end

  test "an untitled video from an unnamed player still reads as a sentence" do
    @medium.user.update_column(:name, nil)

    assert_equal "A new video has been added to your game.",
                 deliver_all.first[:notification].body(:en)
  end

  test "a title without an author names the video and not the person" do
    @medium.user.update_column(:name, nil)
    @medium.update!(title: "Serve breakdown")

    assert_equal "The video \u201CServe breakdown\u201D has been added to your game.",
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
