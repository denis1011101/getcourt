require "test_helper"
require "rack/test"
require "tempfile"

class ScoreRecognitionsControllerTest < ActionDispatch::IntegrationTest
  teardown do
    Array(@tempfiles).each(&:close!)
  end

  test "requires authentication" do
    post score_recognitions_url, as: :json

    assert_response :see_other
    assert_redirected_to new_session_path
  end

  test "returns recognized score for a valid photo" do
    sign_in
    fake_service = Object.new
    fake_service.define_singleton_method(:call) do |_path|
      { sets: [ { top: 6, bottom: 4 } ], top_names: [ "Ivan" ], bottom_names: [ "Petr" ] }
    end

    stub_singleton(Ai::ScoreFromPhotoService, :new, -> { fake_service }) do
      post score_recognitions_url, params: { photo: upload(content_type: "image/jpeg") }

      assert_response :success
      assert_equal 6, response.parsed_body.dig("sets", 0, "top")
      assert_equal [ "Ivan" ], response.parsed_body["top_names"]
    end
  end

  test "rejects an unsupported content type" do
    sign_in

    post score_recognitions_url, params: { photo: upload(content_type: "text/plain") }

    assert_response :unprocessable_entity
    assert response.parsed_body["error"].present?
  end

  test "rejects a photo larger than ten megabytes" do
    sign_in

    post score_recognitions_url, params: { photo: upload(content_type: "image/jpeg", size: 10.megabytes + 1) }

    assert_response :content_too_large
    assert response.parsed_body["error"].present?
  end

  private

  def sign_in
    post session_url, params: { email: "score_recognition_owner@example.com" }
  end

  def upload(content_type:, size: 4)
    tempfile = Tempfile.new([ "score", ".jpg" ])
    tempfile.binmode
    tempfile.write("x" * size)
    tempfile.rewind
    @tempfiles ||= []
    @tempfiles << tempfile
    Rack::Test::UploadedFile.new(tempfile.path, content_type, true, original_filename: "score.jpg")
  end
end
