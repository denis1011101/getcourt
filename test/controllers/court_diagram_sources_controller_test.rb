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

  # Кеш без ревалидации пережил бы деплой: браузер исполнял бы вчерашний Ruby
  # рядом с сегодняшним рантаймом.
  test "the browser revalidates the source instead of trusting its own copy" do
    get court_diagram_source_url

    cache_control = response.headers["Cache-Control"]
    assert_includes cache_control, "must-revalidate"
    assert_includes cache_control, "max-age=0"
  end

  test "an unchanged source comes back as a 304" do
    get court_diagram_source_url
    etag = response.headers["ETag"]

    get court_diagram_source_url, headers: { "HTTP_IF_NONE_MATCH" => etag }

    assert_response :not_modified
    assert_empty response.body
  end
end
