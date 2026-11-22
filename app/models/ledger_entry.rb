class LedgerEntry < ApplicationRecord
  belongs_to :wallet
  belongs_to :wallet_transaction

  validates :amount, numericality: { other_than: 0 }
  validates :wallet_id, uniqueness: { scope: :wallet_transaction_id }
  validate :entry_matches_transaction

  private

  def entry_matches_transaction
    return unless wallet && wallet_transaction && amount

    transaction = wallet_transaction
    valid_entry = case transaction.transaction_type
    when "deposit"
      wallet_id == transaction.target_wallet_id && amount == transaction.amount
    when "withdraw"
      wallet_id == transaction.source_wallet_id && amount == -transaction.amount
    when "transfer"
      (wallet_id == transaction.source_wallet_id && amount == -transaction.amount) ||
        (wallet_id == transaction.target_wallet_id && amount == transaction.amount)
    else
      false
    end
    errors.add(:base, "ledger entry does not match its transaction") unless valid_entry
  end
end
