require "test_helper"

class WalletTransactionTest < ActiveSupport::TestCase
  test "deposit requires a target wallet" do
    user, = user_and_wallet("missing-deposit-target")
    transaction = build_transaction(
      actor: user, transaction_type: "deposit", source_wallet: nil, target_wallet: nil
    )

    assert_not transaction.valid?
    assert_includes transaction.errors[:target_wallet], "is required"
  end

  test "withdrawal requires a source wallet" do
    user, = user_and_wallet("missing-withdraw-source")
    transaction = build_transaction(
      actor: user, transaction_type: "withdraw", source_wallet: nil, target_wallet: nil
    )

    assert_not transaction.valid?
    assert_includes transaction.errors[:source_wallet], "is required"
  end

  test "transfer requires both wallets" do
    user, = user_and_wallet("missing-transfer-wallets")
    transaction = build_transaction(
      actor: user, transaction_type: "transfer", source_wallet: nil, target_wallet: nil
    )

    assert_not transaction.valid?
    assert_includes transaction.errors[:source_wallet], "is required"
    assert_includes transaction.errors[:target_wallet], "is required"
  end

  test "deposit rejects a source wallet" do
    user, wallet = user_and_wallet("deposit-direction")
    transaction = build_transaction(
      actor: user, transaction_type: "deposit", source_wallet: wallet, target_wallet: wallet
    )

    assert_not transaction.valid?
    assert_includes transaction.errors[:source_wallet], "must be nil"
  end

  test "withdrawal rejects a target wallet" do
    user, wallet = user_and_wallet("withdraw-direction")
    transaction = build_transaction(
      actor: user, transaction_type: "withdraw", source_wallet: wallet, target_wallet: wallet
    )

    assert_not transaction.valid?
    assert_includes transaction.errors[:target_wallet], "must be nil"
  end

  test "transfer rejects identical source and target wallets" do
    user, wallet = user_and_wallet("same-wallet")
    transaction = build_transaction(
      actor: user, transaction_type: "transfer", source_wallet: wallet, target_wallet: wallet
    )

    assert_not transaction.valid?
    assert_includes transaction.errors[:target_wallet], "must be different"
  end

  test "amounts with more than two decimal places are rejected" do
    user, wallet = user_and_wallet("precision")
    transaction = build_transaction(
      actor: user, transaction_type: "deposit", source_wallet: nil, target_wallet: wallet,
      amount: "1.234"
    )

    assert_not transaction.valid?
    assert_includes transaction.errors[:amount], "must have at most two decimal places"
  end

  test "zero and negative transaction amounts are rejected" do
    user, wallet = user_and_wallet("nonpositive-amount")

    ["0.00", "-1.00"].each_with_index do |amount, index|
      transaction = build_transaction(
        actor: user, transaction_type: "deposit", source_wallet: nil, target_wallet: wallet,
        amount: amount
      )

      assert_not transaction.valid?, "expected amount #{amount} to be rejected (case #{index})"
      assert_includes transaction.errors[:amount], "must be greater than 0"
    end
  end

  test "database rejects invalid wallet direction without model validations" do
    user, wallet = user_and_wallet("database-direction")
    now = Time.current

    assert_raises(ActiveRecord::StatementInvalid) do
      WalletTransaction.insert_all!([{
        transaction_type: "deposit", actor_id: user.id,
        source_wallet_id: wallet.id, target_wallet_id: wallet.id,
        amount: "1.00", idempotency_key: "invalid-direction",
        request_fingerprint: "e" * 64, created_at: now, updated_at: now
      }])
    end
  end

  private

  def user_and_wallet(suffix)
    user = User.create!(email: "#{suffix}@example.test", password: "test-password")
    [user, Wallet.create!(owner: user, currency: "IDR")]
  end

  def build_transaction(actor:, transaction_type:, source_wallet:, target_wallet:, amount: "1.00")
    WalletTransaction.new(
      actor: actor, transaction_type: transaction_type,
      source_wallet: source_wallet, target_wallet: target_wallet,
      amount: amount, idempotency_key: "model-check",
      request_fingerprint: "f" * 64
    )
  end
end
