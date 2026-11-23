require "test_helper"

class CourtPhotosControllerTest < ActionDispatch::IntegrationTest
  SAMPLE_PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=".freeze

  setup do
    @court = courts(:one)
    @court.update!(moderation_status: "approved")
    @user = User.create!(name: "Court User", email: "court-photo-user@example.com")
    @other = User.create!(name: "Other User", email: "court-photo-other@example.com")
    @admin = User.create!(name: "Court Admin", email: "court-photo-admin@example.com", admin: true)
  end

  test "guest cannot upload photo" do
    assert_no_difference -> { CourtPhoto.count } do
      post court_photos_url(@court), params: { court_photo: { file: png_upload } }
    end
    assert_redirected_to new_session_path
  end

  test "regular user upload creates pending photo and notifies admin" do
    sign_in_as @user
    notified = false
    expected_court_id = @court.id
    original = Telegram::AdminNotifier.method(:notify_court_photo)
    Telegram::AdminNotifier.define_singleton_method(:notify_court_photo) do |photo, base_url:|
      notified = (photo.court_id == expected_court_id && base_url.present?)
    end

    assert_difference -> { @court.court_photos.pending.count }, 1 do
      post court_photos_url(@court), params: { court_photo: { file: png_upload } }
    end

    assert notified
    assert_redirected_to court_url(@court)
  ensure
    Telegram::AdminNotifier.define_singleton_method(:notify_court_photo, original) if original
  end

  test "admin upload is approved immediately" do
    sign_in_as @admin

    assert_difference -> { @court.court_photos.approved.count }, 1 do
      post court_photos_url(@court), params: { court_photo: { file: png_upload } }
    end

    assert_redirected_to court_url(@court)
  end

  test "admin approves and rejects pending photo while non-admin is forbidden" do
    photo = @court.court_photos.build(user: @user, status: "pending")
    photo.file.attach(io: StringIO.new(Base64.decode64(SAMPLE_PNG)), filename: "c.png", content_type: "image/png")
    photo.save!

    sign_in_as @user
    post approve_court_photo_url(@court, photo)
    assert_response :forbidden
    assert photo.reload.pending?

    sign_in_as @admin
    post approve_court_photo_url(@court, photo)
    assert_redirected_to court_url(@court)
    assert photo.reload.approved?

    photo2 = @court.court_photos.build(user: @user, status: "pending")
    photo2.file.attach(io: StringIO.new(Base64.decode64(SAMPLE_PNG)), filename: "c2.png", content_type: "image/png")
    photo2.save!

    post reject_court_photo_url(@court, photo2)
    assert_redirected_to court_url(@court)
    assert photo2.reload.rejected?
  end

  test "author and admin can destroy photo, outsider cannot" do
    photo = @court.court_photos.build(user: @user, status: "pending")
    photo.file.attach(io: StringIO.new(Base64.decode64(SAMPLE_PNG)), filename: "c.png", content_type: "image/png")
    photo.save!

    sign_in_as @other
    delete court_photo_url(@court, photo)
    assert_response :forbidden

    sign_in_as @user
    assert_difference -> { CourtPhoto.count }, -1 do
      delete court_photo_url(@court, photo)
    end
    assert_redirected_to court_url(@court)
  end

  test "cannot upload more than 3 photos to a court" do
    sign_in_as @admin
    3.times do
      post court_photos_url(@court), params: { court_photo: { file: png_upload } }
    end

    assert_no_difference -> { CourtPhoto.count } do
      post court_photos_url(@court), params: { court_photo: { file: png_upload } }
    end
    assert_redirected_to court_url(@court)
    assert_not_nil flash[:alert]
  end

  test "court show renders slider when approved photos exist" do
    sign_in_as @admin
    post court_photos_url(@court), params: { court_photo: { file: png_upload } }
    post court_photos_url(@court), params: { court_photo: { file: png_upload } }

    get court_url(@court)
    assert_response :success
    assert_includes response.body, "court-photos-slider"
  end

  private

  def png_upload
    Rack::Test::UploadedFile.new(StringIO.new(Base64.decode64(SAMPLE_PNG)), "image/png", original_filename: "court.png")
  end

  def sign_in_as(user)
    post session_url, params: { email: user.email }
  end
end
