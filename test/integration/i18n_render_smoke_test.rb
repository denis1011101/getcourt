require "test_helper"

class I18nRenderSmokeTest < ActionDispatch::IntegrationTest
  PUBLIC = %w[/ /courts /coaches /tournaments /tennis_life /tennis_life/statistics
              /ntrp_level_guide /tennis_formats_and_rules /partnership /mission
              /contacts /privacy_policy /searches /sign_in]

  %w[en ru es].each do |loc|
    PUBLIC.each do |path|
      test "#{loc} public #{path}" do
        get path, params: { locale: loc }
        follow_redirect! while response.redirect?
        assert_no_match(/translation missing/i, response.body, "#{loc} #{path}")
      end
    end

    test "#{loc} authenticated pages" do
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
        get path, params: { locale: loc }
        next if response.status == 404
        follow_redirect! while response.redirect?
        assert_no_match(/translation missing/i, response.body, "#{loc} #{path}")
      end
    end
  end
end
