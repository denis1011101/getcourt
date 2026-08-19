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
    deliveries = []

    with_stubbed_singleton_method(NotificationDelivery, :deliver, ->(**args) { deliveries << args }) do
      SendTrainingVideoJob.perform_now(@medium.id)
    end

    assert_equal [ @approved.id ], deliveries.map { |delivery| delivery[:user].id }
    notification = deliveries.first[:notification]
    assert_equal "Training video for your game", notification.subject(:en)
    assert_equal "Watch video", notification.actions(:en).first[:label]
    assert_match %r{http://example.com/rails/active_storage/blobs/redirect/}, notification.actions(:en).first[:url]
  end

  test "does not deliver a hidden video" do
    deliveries = []
    @medium.hide!

    with_stubbed_singleton_method(NotificationDelivery, :deliver, ->(**args) { deliveries << args }) do
      SendTrainingVideoJob.perform_now(@medium.id)
    end

    assert_empty deliveries
  end

  private

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
