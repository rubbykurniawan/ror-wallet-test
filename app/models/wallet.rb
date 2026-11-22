class Wallet < ApplicationRecord
  CURRENCY = "IDR".freeze

  belongs_to :owner, polymorphic: true
  has_many :ledger_entries, dependent: :restrict_with_exception
  has_many :outgoing_transactions, class_name: "WalletTransaction",
    foreign_key: :source_wallet_id, dependent: :restrict_with_exception
  has_many :incoming_transactions, class_name: "WalletTransaction",
    foreign_key: :target_wallet_id, dependent: :restrict_with_exception

  validates :currency, inclusion: { in: [ CURRENCY ] }
  validates :owner_id, uniqueness: { scope: %i[owner_type currency] }
  validate :owner_type_is_registered

  def balance
    BigDecimal(ledger_entries.sum(:amount).to_s)
  end

  private

  def owner_type_is_registered
    return if WalletOwner::Registry.registered?(owner_type)

    errors.add(:owner_type, "is not registered as a wallet owner")
  end
end
