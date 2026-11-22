require "test_helper"

class WalletTest < ActiveSupport::TestCase
  test "User, Team, and Stock can each own a polymorphic wallet" do
    owners = [
      User.create!(email: "user@example.test", password: "test-password"),
      Team.create!(name: "Payments"),
      Stock.create!(symbol: "ACME")
    ]

    wallets = owners.map { |owner| Wallet.create!(owner: owner, currency: "IDR") }

    assert_equal owners, wallets.map { |wallet| wallet.reload.owner }
  end

  test "balance is derived from signed ledger entries" do
    user = User.create!(email: "owner@example.test", password: "test-password")
    wallet = Wallet.create!(owner: user, currency: "IDR")
    deposit = WalletTransaction.create!(
      transaction_type: "deposit", target_wallet: wallet, amount: "100.00",
      actor: user, idempotency_key: "deposit-1", request_fingerprint: "a" * 64
    )
    withdrawal = WalletTransaction.create!(
      transaction_type: "withdraw", source_wallet: wallet, amount: "25.50",
      actor: user, idempotency_key: "withdraw-1", request_fingerprint: "b" * 64
    )
    LedgerEntry.create!(wallet: wallet, wallet_transaction: deposit, amount: "100.00")
    LedgerEntry.create!(wallet: wallet, wallet_transaction: withdrawal, amount: "-25.50")

    assert_equal BigDecimal("74.50"), wallet.reload.balance
  end

  test "one wallet per owner and currency is enforced" do
    user = User.create!(email: "single-wallet@example.test", password: "test-password")
    Wallet.create!(owner: user, currency: "IDR")

    duplicate = Wallet.new(owner: user, currency: "IDR")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:owner_id], "has already been taken"
  end
end
