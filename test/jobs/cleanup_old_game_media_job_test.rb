require "test_helper"

class CleanupOldGameMediaJobTest < ActiveJob::TestCase
  SAMPLE_PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=".freeze

  setup do
    @game = games(:feed_upcoming)
    @user = users(:one)
  end

  test "destroys media older than a month" do
    stale = create_medium(created_at: 5.weeks.ago)

    CleanupOldGameMediaJob.perform_now

    assert_nil GameMedium.find_by(id: stale.id)
  end

  test "keeps media younger than a month" do
    fresh = create_medium(created_at: 3.weeks.ago)

    CleanupOldGameMediaJob.perform_now

    assert_not_nil GameMedium.find_by(id: fresh.id)
  end

  test "takes hidden media too — moderation does not free the disk on its own" do
    hidden = create_medium(created_at: 5.weeks.ago)
    hidden.update_column(:hidden_at, 5.weeks.ago)

    CleanupOldGameMediaJob.perform_now

    assert_nil GameMedium.find_by(id: hidden.id)
  end

  test "detaches the file so Active Storage can drop it from disk" do
    create_medium(created_at: 5.weeks.ago)

    assert_difference -> { ActiveStorage::Attachment.where(record_type: "GameMedium").count }, -1 do
      CleanupOldGameMediaJob.perform_now
    end
  end

  test "honours a custom retention window" do
    medium = create_medium(created_at: 10.days.ago)

    CleanupOldGameMediaJob.perform_now(retention: 1.week)

    assert_nil GameMedium.find_by(id: medium.id)
  end

  private

  def create_medium(created_at:, filename: "shot.png")
    medium = GameMedium.new(game: @game, user: @user)
    medium.file.attach(
      io: StringIO.new(Base64.decode64(SAMPLE_PNG)),
      filename: filename,
      content_type: "image/png",
      identify: false
    )
    medium.save!
    medium.update_column(:created_at, created_at)
    medium
  end
end
