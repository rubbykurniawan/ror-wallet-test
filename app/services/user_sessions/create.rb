require "digest"
require "securerandom"

module UserSessions
  class Create
    LIFETIME = 12.hours
    Result = Struct.new(:session, :token, :csrf_token, keyword_init: true)

    def self.call(user:)
      token = SecureRandom.urlsafe_base64(32)
      csrf_token = SecureRandom.urlsafe_base64(32)
      session = user.user_sessions.create!(
        token_digest: Digest::SHA256.hexdigest(token),
        csrf_token_digest: Digest::SHA256.hexdigest(csrf_token),
        expires_at: LIFETIME.from_now
      )

      Result.new(session: session, token: token, csrf_token: csrf_token)
    end
  end
end
