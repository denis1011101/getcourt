require "test_helper"

class I18nRenderSmokeTest < ActionDispatch::IntegrationTest
  PUBLIC = %w[/ /courts /coaches /tournaments /tennis_life /tennis_life/classic /tennis_life/statistics
              /ntrp_level_guide /tennis_formats_and_rules /partnership /mission
              /contacts /privacy_policy /searches /sign_in]

  %w[en ru es].each do |loc|
    PUBLIC.each do |path|
      test "#{loc} public #{path}" do
        host! "#{loc}.example.com"
        get path
        follow_redirect! while response.redirect?
        assert_no_match(/translation missing/i, response.body, "#{loc} #{path}")
      end
    end

    test "#{loc} tennis life feed" do
      host! "#{loc}.example.com"
      cursor = TennisLife::Feed::Cursor.start(seed: 123, snapshot_ts: Time.current)
      path = tennis_life_feed_path(cursor: cursor.to_param)
      kinds = []

      20.times do
        get path
        assert_response :success
        assert_no_match(/translation missing/i, response.body, "#{loc} tennis life feed")
        kinds.concat(response.body.scan(/data-feed-card-id="([^"]+)"/).flatten.map { |id| id.split(":", 2).first })

        link_tag = response.body[/<a\b(?=[^>]*data-infinite-feed-target="link")[^>]*>/]
        encoded_path = link_tag&.[](/href="([^"]+)"/, 1)
        path = encoded_path ? CGI.unescapeHTML(encoded_path) : nil
        break unless path
      end

      assert_nil path, "#{loc} tennis life feed did not finish"
      assert_equal %w[court_update fact featured_match match player scoreboard telegram_post tournament upcoming_game urgent_search], kinds.uniq.sort
    end

    test "#{loc} authenticated pages" do
      host! "#{loc}.example.com"
      user = users(:one)
      post session_url, params: { email: user.email }
      follow_redirect! while response.redirect?

      game  = games(:one)
      court = courts(:one)
      paths = [
        "/account", "/account/profile", "/account/security",
        "/account/notifications", "/account/courts", "/account/games",
        "/games/new", "/courts/new",
        "/games/#{game.id}", "/games/#{game.id}/edit",
        "/courts/#{court.id}", "/courts/#{court.id}/edit"
      ]
      paths.each do |path|
        get path
        next if response.status == 404
        follow_redirect! while response.redirect?
        assert_no_match(/translation missing/i, response.body, "#{loc} #{path}")
      end
    end
  end
end
