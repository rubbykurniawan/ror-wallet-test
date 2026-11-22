class Stock < ApplicationRecord
  include WalletOwner

  normalizes :symbol, with: ->(symbol) { symbol.strip.upcase }

  validates :symbol, presence: true, uniqueness: true
end
