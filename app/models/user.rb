class User < ApplicationRecord
  include WalletOwner

  has_secure_password

  has_many :user_sessions, dependent: :destroy
  has_many :wallet_transactions, foreign_key: :actor_id, dependent: :restrict_with_exception

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, uniqueness: true
end
