require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "api-token-owner@example.com", email_verified_at: Time.current)
  end

  test "a fresh token lives half a year and is recognised" do
    token = ApiToken.issue_for(@user)

    assert_in_delta ApiToken::LIFETIME.from_now.to_i, token.expires_at.to_i, 5
    assert_equal token, ApiToken.authenticate(token.token)
  end

  test "issuing a new token revokes the previous one" do
    old = ApiToken.issue_for(@user)
    fresh = ApiToken.issue_for(@user)

    assert_not_nil old.reload.revoked_at
    assert_nil ApiToken.authenticate(old.token)
    assert_equal fresh, ApiToken.authenticate(fresh.token)
    assert_equal [ fresh ], @user.api_tokens.active.to_a
  end

  test "a revoked or expired token opens nothing" do
    revoked = ApiToken.issue_for(@user)
    revoked.revoke!
    expired = ApiToken.issue_for(@user)
    expired.update_columns(expires_at: 1.day.ago)

    assert_nil ApiToken.authenticate(revoked.token)
    assert_nil ApiToken.authenticate(expired.token)
    assert_nil ApiToken.authenticate("")
  end

  test "a request pushes the expiry out — but writes at most once a day" do
    token = ApiToken.issue_for(@user)
    token.update_columns(expires_at: 1.month.from_now, last_used_at: 2.days.ago)

    ApiToken.authenticate(token.token)

    assert_in_delta ApiToken::LIFETIME.from_now.to_i, token.reload.expires_at.to_i, 5

    token.update_columns(expires_at: 1.month.from_now, last_used_at: 1.hour.ago)
    ApiToken.authenticate(token.token)

    assert_in_delta 1.month.from_now.to_i, token.reload.expires_at.to_i, 5
  end
end
