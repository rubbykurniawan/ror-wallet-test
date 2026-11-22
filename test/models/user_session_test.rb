require "test_helper"

class UserSessionTest < ActiveSupport::TestCase
  test "a user session is active before expiry and can be revoked" do
    user = User.create!(email: "session@example.test", password: "test-password")
    user_session = UserSession.create!(
      user: user, token_digest: "a" * 64, csrf_token_digest: "b" * 64,
      expires_at: 1.hour.from_now
    )

    assert user_session.active?

    user_session.revoke!

    assert_not user_session.reload.active?
  end

  test "token digests cannot be reused across sessions" do
    user = User.create!(email: "session-unique@example.test", password: "test-password")
    attributes = {
      user: user, token_digest: "c" * 64, csrf_token_digest: "d" * 64,
      expires_at: 1.hour.from_now
    }
    UserSession.create!(attributes)

    duplicate = UserSession.new(attributes)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:token_digest], "has already been taken"
  end
end
