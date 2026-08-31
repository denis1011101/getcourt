require "test_helper"

class CourtDiagramSourcesControllerTest < ActionDispatch::IntegrationTest
  test "the editor source is public and cacheable" do
    get court_diagram_source_url

    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_includes response.body, "class Editor"
    assert_includes response.body, "def normalize"
    assert response.headers["ETag"].present?
  end
end
