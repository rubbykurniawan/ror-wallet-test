require "test_helper"

class LedgerEntryTest < ActiveSupport::TestCase
  test "the database rejects ledger entry updates" do
    _transaction, entry = create_deposit_entry

    assert_raises(ActiveRecord::StatementInvalid) do
      entry.update_column(:amount, BigDecimal("9.00"))
    end
  end

  test "the database rejects ledger entry deletes" do
    _transaction, entry = create_deposit_entry

    assert_raises(ActiveRecord::StatementInvalid) do
      LedgerEntry.where(id: entry.id).delete_all
    end
  end

  test "the database rejects changing a transaction after it has ledger entries" do
    transaction, = create_deposit_entry

    assert_raises(ActiveRecord::StatementInvalid) do
      transaction.update_column(:amount, BigDecimal("9.00"))
    end
  end

  test "a committed transaction must have its required ledger entries" do
    user = User.create!(email: "incomplete@example.test", password: "test-password")
    wallet = Wallet.create!(owner: user, currency: "IDR")

    assert_raises(ActiveRecord::StatementInvalid) do
      Wallet.transaction do
        WalletTransaction.create!(
          transaction_type: "deposit", target_wallet: wallet, amount: "10.00",
          actor: user, idempotency_key: "incomplete-1", request_fingerprint: "c" * 64
        )
        ActiveRecord::Base.connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
      end
    end
  end

  private

  def create_deposit_entry
    user = User.create!(email: "ledger@example.test", password: "test-password")
    wallet = Wallet.create!(owner: user, currency: "IDR")
    transaction = WalletTransaction.create!(
      transaction_type: "deposit", target_wallet: wallet, amount: "10.00",
      actor: user, idempotency_key: "ledger-1", request_fingerprint: "d" * 64
    )
    entry = LedgerEntry.create!(wallet: wallet, wallet_transaction: transaction, amount: "10.00")

    [transaction, entry]
  end
end
