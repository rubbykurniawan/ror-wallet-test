class UserSession < ApplicationRecord
  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true,
    format: { with: /\A[0-9a-f]{64}\z/ }
  validates :csrf_token_digest, presence: true,
    format: { with: /\A[0-9a-f]{64}\z/ }
  validates :expires_at, presence: true

  def active?
    revoked_at.nil? && expires_at.future?
  end

  def revoke!
    update!(revoked_at: Time.current) unless revoked_at
  end
end
