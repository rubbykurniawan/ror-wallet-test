class Team < ApplicationRecord
  include WalletOwner

  validates :name, presence: true
end
