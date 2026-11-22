class WalletTransaction < ApplicationRecord
  TYPES = %w[deposit withdraw transfer].freeze

  belongs_to :actor, class_name: "User"
  belongs_to :source_wallet, class_name: "Wallet", optional: true
  belongs_to :target_wallet, class_name: "Wallet", optional: true
  has_many :ledger_entries, dependent: :restrict_with_exception

  validates :transaction_type, inclusion: { in: TYPES }
  validates :amount, numericality: { greater_than: 0 }
  validates :idempotency_key, presence: true, length: { maximum: 255 },
    uniqueness: { scope: :actor_id }
  validates :request_fingerprint, format: { with: /\A[0-9a-f]{64}\z/ }
  validate :amount_has_at_most_two_decimal_places
  validate :validate_wallets

  private

  def amount_has_at_most_two_decimal_places
    raw_amount = amount_before_type_cast
    return if raw_amount.blank?

    precise_amount = BigDecimal(raw_amount.to_s)
    return if precise_amount == precise_amount.round(2)

    errors.add(:amount, "must have at most two decimal places")
  rescue ArgumentError
    nil
  end

  def validate_wallets
    case transaction_type
    when "deposit"
      errors.add(:source_wallet, "must be nil") if source_wallet
      errors.add(:target_wallet, "is required") unless target_wallet
    when "withdraw"
      errors.add(:source_wallet, "is required") unless source_wallet
      errors.add(:target_wallet, "must be nil") if target_wallet
    when "transfer"
      errors.add(:source_wallet, "is required") unless source_wallet
      errors.add(:target_wallet, "is required") unless target_wallet
      return unless source_wallet && target_wallet

      errors.add(:target_wallet, "must be different") if source_wallet_id == target_wallet_id
      errors.add(:target_wallet, "currency mismatch") if source_wallet.currency != target_wallet.currency
    end
  end
end
