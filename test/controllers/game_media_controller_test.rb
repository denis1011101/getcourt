require "test_helper"

class GameMediaControllerTest < ActionDispatch::IntegrationTest
  SAMPLE_PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=".freeze
  SAMPLE_MP4 = "\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom".b.freeze

  setup do
    @game = games(:feed_upcoming)
    # Владелец в фикстурах без email, а вход в тестах идёт по нему.
    @owner = @game.user
    @owner.update!(email: "media-owner@example.com")
    @participant = User.create!(name: "Media Participant", email: "media-participant@example.com")
    @outsider = User.create!(name: "Media Outsider", email: "media-outsider@example.com")
    @game.participations.create!(user: @participant)
  end

  test "the organizer can attach a photo" do
    sign_in_as @owner

    assert_difference -> { @game.game_media.count }, 1 do
      post game_media_path(@game), params: { file: upload }
    end

    assert_redirected_to game_path(@game)
  end

  test "a player of the game can attach one too" do
    sign_in_as @participant

    assert_difference -> { @game.game_media.count }, 1 do
      post game_media_path(@game), params: { file: upload }
    end
  end

  test "the organizer can queue an uploaded video for the players" do
    sign_in_as @owner

    assert_enqueued_jobs 1, only: SendTrainingVideoJob do
      post game_media_path(@game), params: { file: video_upload, notify_participants: "1" }
    end

    assert_redirected_to game_path(@game)
  end

  test "a photo with the box ticked is uploaded but says nothing was sent" do
    sign_in_as @owner

    assert_no_enqueued_jobs only: SendTrainingVideoJob do
      assert_difference -> { @game.game_media.count }, 1 do
        post game_media_path(@game), params: { file: upload, notify_participants: "1" }
      end
    end

    assert_equal I18n.t("game_media.uploaded_videos_only"), flash[:notice]
  end

  test "a player cannot queue an uploaded video for everyone" do
    sign_in_as @participant

    assert_no_enqueued_jobs only: SendTrainingVideoJob do
      post game_media_path(@game), params: { file: video_upload, notify_participants: "1" }
    end
  end

  test "an accepted coach can queue an uploaded video for the players" do
    coach = User.create!(name: "Media Coach", email: "media-coach@example.com", coach: true)
    @game.update!(with_coach: true, recurring: true, coach: coach)
    @game.update!(coach_invitation_status: "accepted")
    sign_in_as coach

    assert_enqueued_jobs 1, only: SendTrainingVideoJob do
      assert_difference -> { @game.game_media.count }, 1 do
        post game_media_path(@game), params: { file: video_upload, notify_participants: "1" }
      end
    end

    assert_redirected_to game_path(@game)
  end

  test "someone with no part in the game cannot" do
    sign_in_as @outsider

    assert_no_difference -> { @game.game_media.count } do
      post game_media_path(@game), params: { file: upload }
    end

    assert_redirected_to game_path(@game)
  end

  test "signed out visitors are sent to sign in" do
    assert_no_difference -> { @game.game_media.count } do
      post game_media_path(@game), params: { file: upload }
    end

    assert_redirected_to new_session_path
  end

  test "an invalid file comes back with the reason instead of a 500" do
    sign_in_as @owner

    assert_no_difference -> { @game.game_media.count } do
      post game_media_path(@game), params: {
        file: Rack::Test::UploadedFile.new(StringIO.new("just some text"), "application/pdf", original_filename: "nope.pdf")
      }
    end

    assert_redirected_to game_path(@game)
    assert flash[:alert].present?
  end

  test "the author deletes their own attachment" do
    sign_in_as @participant
    post game_media_path(@game), params: { file: upload }
    medium = @game.game_media.last

    assert_difference -> { GameMedium.count }, -1 do
      delete game_medium_path(@game, medium)
    end
  end

  test "an admin hides someone else's attachment rather than deleting it" do
    sign_in_as @participant
    post game_media_path(@game), params: { file: upload }
    medium = @game.game_media.last

    admin = User.create!(name: "Media Admin", email: "media-admin@example.com", admin: true)
    sign_in_as admin

    assert_no_difference -> { GameMedium.count } do
      delete game_medium_path(@game, medium)
    end

    assert medium.reload.hidden?
  end

  test "a bystander can neither delete nor hide" do
    sign_in_as @participant
    post game_media_path(@game), params: { file: upload }
    medium = @game.game_media.last

    sign_in_as @outsider
    delete game_medium_path(@game, medium)

    assert_not medium.reload.hidden?
    assert GameMedium.exists?(medium.id)
  end

  test "the title is optional and stays empty when nobody typed one" do
    sign_in_as @participant
    post game_media_path(@game), params: { file: upload }

    assert_nil @game.game_media.last.title
  end

  test "a typed title is saved with the upload" do
    sign_in_as @participant
    post game_media_path(@game), params: { file: upload, title: "  Serve breakdown  " }

    assert_equal "Serve breakdown", @game.game_media.last.title
  end

  test "a fresh upload stays out of Tennis Life until someone ticks the box" do
    sign_in_as @participant
    post game_media_path(@game), params: { file: upload }

    assert_not @game.game_media.last.show_in_feed?
  end

  test "the author turns the Tennis Life checkbox on and back off" do
    sign_in_as @participant
    post game_media_path(@game), params: { file: upload }
    medium = @game.game_media.last

    patch game_medium_path(@game, medium), params: { show_in_feed: "1" }
    assert medium.reload.show_in_feed?

    patch game_medium_path(@game, medium), params: { show_in_feed: "0" }
    assert_not medium.reload.show_in_feed?
  end

  test "an admin can switch it for someone else's attachment" do
    sign_in_as @participant
    post game_media_path(@game), params: { file: upload }
    medium = @game.game_media.last

    admin = User.create!(name: "Media Admin Feed", email: "media-admin-feed@example.com", admin: true)
    sign_in_as admin
    patch game_medium_path(@game, medium), params: { show_in_feed: "1" }

    assert medium.reload.show_in_feed?
  end

  test "a bystander cannot put someone else's attachment on the front page" do
    sign_in_as @participant
    post game_media_path(@game), params: { file: upload }
    medium = @game.game_media.last

    sign_in_as @outsider
    patch game_medium_path(@game, medium), params: { show_in_feed: "1" }

    assert_not medium.reload.show_in_feed?
    assert_equal I18n.t("game_media.not_allowed"), flash[:alert]
  end

  private

  def upload(content_type: "image/png", filename: "shot.png")
    Rack::Test::UploadedFile.new(StringIO.new(Base64.decode64(SAMPLE_PNG)), content_type, original_filename: filename)
  end

  def video_upload
    Rack::Test::UploadedFile.new(StringIO.new(SAMPLE_MP4), "video/mp4", original_filename: "lesson.mp4")
  end

  def sign_in_as(user)
    post session_url, params: { email: user.email }
  end
end
