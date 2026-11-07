require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "should get contacts" do
    get contacts_url
    assert_response :success
  end

  test "should get mission" do
    get mission_url
    assert_response :success
  end

  test "more lists the More menu links for guests" do
    get more_url
    assert_response :success
    assert_select "a[href=?]", tournaments_path
    assert_select "a[href=?]", edit_account_path, count: 0
  end

  # pages_nav partial: each page shows links to all others but not itself
  {
    contacts:              -> { contacts_path },
    mission:               -> { mission_path },
    partnership:           -> { partnership_path },
    ntrp_level_guide:      -> { ntrp_level_guide_path },
    tennis_formats_rules:  -> { tennis_formats_and_rules_path },
    api_and_mcp:           -> { api_and_mcp_path }
  }.each do |page, path_proc|
    test "#{page} renders pages_nav without self-link" do
      get instance_exec(&path_proc)
      assert_response :success

      all_paths = [
        contacts_path, mission_path, partnership_path,
        ntrp_level_guide_path, tennis_formats_and_rules_path, api_and_mcp_path, coaches_path
      ]
      current_path = instance_exec(&path_proc)

      (all_paths - [ current_path ]).each do |other|
        assert_select "a[href='#{other}']", minimum: 1
      end

      # self-link must not appear inside the nav div
      assert_select "div.mt-6 a[href='#{current_path}']", count: 0
    end
  end

  PagesController::REFERENCE_PAGES.each do |page|
    test "#{page} renders HTML by default with Vary and alternate link" do
      get url_for(controller: "pages", action: page, only_path: false)
      assert_response :success
      assert_includes response.media_type, "text/html"
      assert_includes response.headers["Vary"].to_s, "Accept"

      md_url = url_for(controller: "pages", action: page, only_path: false, format: :md)
      assert_includes response.headers["Link"].to_s, %(<#{md_url}>; rel="alternate"; type="text/markdown")
      assert_select %(link[rel="alternate"][type="text/markdown"][href="#{md_url}"])
    end

    test "#{page}.md renders Markdown without layout" do
      get url_for(controller: "pages", action: page, only_path: false, format: :md)
      assert_response :success
      assert_equal "text/markdown; charset=utf-8", response.content_type
      assert_includes response.headers["Vary"].to_s, "Accept"

      html_url = url_for(controller: "pages", action: page, only_path: false)
      assert_includes response.headers["Link"].to_s, %(<#{html_url}>; rel="alternate"; type="text/html")

      assert_match(/\A#\s+/, response.body.strip)
      assert_no_match(/<html|<body|<div/i, response.body)
    end
  end

  test "api_and_mcp renders valid markdown without escaped HTML entities in code" do
    get api_and_mcp_url(format: :md)
    assert_response :success
    assert_includes response.body, "Authorization: Bearer <token>"
    assert_not_includes response.body, "&lt;token&gt;"
    assert_includes response.body, "GET https://getcourt.co/api/v1/games"
  end

  test "reference pages negotiate text/markdown when requested" do
    get api_and_mcp_url, headers: { "Accept" => "text/markdown" }
    assert_response :success
    assert_equal "text/markdown; charset=utf-8", response.content_type
    assert_includes response.headers["Vary"].to_s, "Accept"
    assert_match(/\A#\s+/, response.body.strip)
  end

  test "reference pages prefer HTML when HTML and MD have equal positive q" do
    get api_and_mcp_url, headers: { "Accept" => "text/markdown, text/html" }
    assert_response :success
    assert_includes response.media_type, "text/html"
  end

  test "reference pages negotiate Markdown when md q is strictly higher than html q" do
    get api_and_mcp_url, headers: { "Accept" => "text/html;q=0.8, text/markdown;q=0.9" }
    assert_response :success
    assert_equal "text/markdown; charset=utf-8", response.content_type
  end

  test "reference pages prefer HTML when html q is strictly higher than md q" do
    get api_and_mcp_url, headers: { "Accept" => "text/html, text/markdown;q=0.9" }
    assert_response :success
    assert_includes response.media_type, "text/html"
  end

  test "reference pages return HTML for wildcard Accept" do
    get api_and_mcp_url, headers: { "Accept" => "*/*" }
    assert_response :success
    assert_includes response.media_type, "text/html"
  end

  test "reference pages return HTML for text wildcard Accept" do
    get api_and_mcp_url, headers: { "Accept" => "text/*" }
    assert_response :success
    assert_includes response.media_type, "text/html"
  end

  test "reference pages return 406 when text/markdown is explicitly banned without other ranges" do
    get api_and_mcp_url, headers: { "Accept" => "text/markdown;q=0" }
    assert_response :not_acceptable
  end

  test "reference pages return HTML when text/markdown is banned but wildcard is allowed" do
    get api_and_mcp_url, headers: { "Accept" => "text/markdown;q=0, */*;q=1" }
    assert_response :success
    assert_includes response.media_type, "text/html"
  end

  test "reference pages return 406 when text/html is banned even if wildcard is present" do
    get api_and_mcp_url, headers: { "Accept" => "text/html;q=0, */*;q=1" }
    assert_response :not_acceptable
  end

  test "reference pages return 406 for unsupported formats" do
    get api_and_mcp_url, headers: { "Accept" => "application/json" }
    assert_response :not_acceptable
    assert_includes response.headers["Vary"].to_s, "Accept"
  end

  test "reference pages return 406 for unsupported URL format extension" do
    get api_and_mcp_url(format: :json)
    assert_response :not_acceptable
    assert_includes response.headers["Vary"].to_s, "Accept"
  end

  test "reference pages do not treat application/xhtml+xml as HTML representation" do
    get api_and_mcp_url, headers: { "Accept" => "application/xhtml+xml" }
    assert_response :not_acceptable
    assert_includes response.headers["Vary"].to_s, "Accept"
  end

  test "reference pages return 406 when text/html is banned even if application/xhtml+xml has q=1" do
    get api_and_mcp_url, headers: { "Accept" => "text/html;q=0, application/xhtml+xml;q=1" }
    assert_response :not_acceptable
    assert_includes response.headers["Vary"].to_s, "Accept"
  end

  test "reference pages correctly parse quoted parameters in Accept header" do
    get api_and_mcp_url, headers: { "Accept" => 'text/markdown;profile="a,b";q=0, text/html;q=0.5' }
    assert_response :success
    assert_includes response.media_type, "text/html"

    get api_and_mcp_url, headers: { "Accept" => 'text/markdown;profile="a;b";q=1' }
    assert_response :success
    assert_equal "text/markdown; charset=utf-8", response.content_type
  end
end
