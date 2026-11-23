require "test_helper"

class CourtPhotoTest < ActiveSupport::TestCase
  SAMPLE_PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=".freeze

  setup do
    @court = courts(:one)
    @court.update!(moderation_status: "approved")
    @user = User.create!(name: "Photo User", email: "photo-model-user@example.com")
    @admin = User.create!(name: "Photo Admin", email: "photo-model-admin@example.com", admin: true)
  end

  test "validates file attachment and image content type" do
    photo = @court.court_photos.build(user: @user)
    assert_not photo.valid?

    photo.file.attach(io: StringIO.new("not an image"), filename: "doc.pdf", content_type: "application/pdf")
    assert_not photo.valid?

    attach_png(photo)
    assert photo.valid?
  end

  test "enforces maximum of 3 active photos per court" do
    3.times do
      photo = @court.court_photos.build(user: @user, status: "approved")
      attach_png(photo)
      assert photo.save!
    end

    fourth = @court.court_photos.build(user: @user, status: "pending")
    attach_png(fourth)
    assert_not fourth.valid?
  end

  test "rejected photos do not block uploading up to 3 active photos" do
    rejected = @court.court_photos.build(user: @user, status: "rejected")
    attach_png(rejected)
    rejected.save!

    3.times do
      photo = @court.court_photos.build(user: @user, status: "pending")
      attach_png(photo)
      assert photo.save!
    end
  end

  test "only admin can approve or reject pending photo" do
    photo = @court.court_photos.build(user: @user, status: "pending")
    attach_png(photo)
    photo.save!

    assert_not photo.approve_by!(@user)
    assert photo.reload.pending?

    assert photo.approve_by!(@admin)
    assert photo.reload.approved?
    assert_equal @admin, photo.reviewed_by
    assert_not_nil photo.reviewed_at

    another = @court.court_photos.build(user: @user, status: "pending")
    attach_png(another)
    another.save!

    assert_not another.reject_by!(@user)
    assert another.reject_by!(@admin)
    assert another.reload.rejected?
  end

  test "destroying author destroys their photos and destroying admin nullifies reviewed_by" do
    photo_by_user = @court.court_photos.build(user: @user, status: "pending")
    attach_png(photo_by_user)
    photo_by_user.save!

    reviewer_other_user = User.create!(name: "Second Author", email: "second-author@example.com")
    reviewed_photo = @court.court_photos.build(user: reviewer_other_user, status: "pending")
    attach_png(reviewed_photo)
    reviewed_photo.save!
    assert reviewed_photo.approve_by!(@admin)

    assert_difference -> { CourtPhoto.count }, -1 do
      @user.destroy!
    end

    @admin.destroy!
    assert_nil reviewed_photo.reload.reviewed_by_id
    assert reviewed_photo.approved?
  end

  private

  def attach_png(photo)
    photo.file.attach(
      io: StringIO.new(Base64.decode64(SAMPLE_PNG)),
      filename: "court.png",
      content_type: "image/png"
    )
  end
end
