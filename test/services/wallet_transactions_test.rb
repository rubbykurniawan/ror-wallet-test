require "test_helper"

class WalletTransactionsTest < ActiveSupport::TestCase
  setup do
    @actor = User.create!(email: "actor@example.test", password: "correct horse battery staple")
    @other_user = User.create!(email: "other@example.test", password: "correct horse battery staple")
    @source = Wallet.create!(owner: @actor, currency: "IDR")
    @target = Wallet.create!(owner: @other_user, currency: "IDR")
  end

  test "deposit credits a target wallet and replays an identical idempotent request" do
    transaction = WalletTransactions::Deposit.call(
      actor: @actor, target_wallet: @source, amount: "100.00", idempotency_key: "deposit-1"
    )

    replay = WalletTransactions::Deposit.call(
      actor: @actor, target_wallet: @source, amount: "100.00", idempotency_key: "deposit-1"
    )

    assert_equal transaction.id, replay.id
    assert_equal BigDecimal("100"), @source.balance
    assert_equal [ BigDecimal("100") ], transaction.ledger_entries.pluck(:amount)
  end

  test "withdrawal debits only available funds and rejects overdrafts" do
    WalletTransactions::Deposit.call(actor: @actor, target_wallet: @source, amount: 80, idempotency_key: "d1")

    transaction = WalletTransactions::Withdrawal.call(
      actor: @actor, source_wallet: @source, amount: 30, idempotency_key: "w1"
    )

    assert_equal [ BigDecimal("-30") ], transaction.ledger_entries.pluck(:amount)
    assert_equal BigDecimal("50"), @source.balance
    assert_raises(WalletTransactions::InsufficientFunds) do
      WalletTransactions::Withdrawal.call(actor: @actor, source_wallet: @source, amount: 51, idempotency_key: "w2")
    end
    assert_equal BigDecimal("50"), @source.balance
  end

  test "transfer writes balanced debit and credit entries" do
    WalletTransactions::Deposit.call(actor: @actor, target_wallet: @source, amount: 100, idempotency_key: "d1")

    transaction = WalletTransactions::Transfer.call(
      actor: @actor, source_wallet: @source, target_wallet: @target, amount: 35, idempotency_key: "t1"
    )

    assert_equal [ BigDecimal("-35"), BigDecimal("35") ], transaction.ledger_entries.order(:wallet_id).pluck(:amount)
    assert_equal BigDecimal("65"), @source.balance
    assert_equal BigDecimal("35"), @target.balance
  end

  test "changed payload with an existing actor key conflicts" do
    WalletTransactions::Deposit.call(actor: @actor, target_wallet: @source, amount: 10, idempotency_key: "same")

    assert_raises(WalletTransactions::IdempotencyConflict) do
      WalletTransactions::Deposit.call(actor: @actor, target_wallet: @source, amount: 11, idempotency_key: "same")
    end
  end

  test "invalid amount and unauthorized wallet directions are rejected" do
    assert_raises(WalletTransactions::InvalidRequest) do
      WalletTransactions::Deposit.call(actor: @actor, target_wallet: @source, amount: "1.001", idempotency_key: "bad")
    end
    assert_raises(WalletTransactions::Forbidden) do
      WalletTransactions::Withdrawal.call(actor: @actor, source_wallet: @target, amount: 1, idempotency_key: "forbidden")
    end
    assert_raises(WalletTransactions::Forbidden) do
      WalletTransactions::Deposit.call(actor: @actor, target_wallet: @target, amount: 1, idempotency_key: "forbidden-deposit")
    end
  end

  test "transfer to a team wallet is permitted but debit from it is forbidden" do
    team_wallet = Wallet.create!(owner: Team.create!(name: "Operations"), currency: "IDR")
    WalletTransactions::Deposit.call(actor: @actor, target_wallet: @source, amount: 20, idempotency_key: "d1")

    WalletTransactions::Transfer.call(
      actor: @actor, source_wallet: @source, target_wallet: team_wallet, amount: 5, idempotency_key: "team-transfer"
    )

    assert_equal BigDecimal("5"), team_wallet.balance
    assert_raises(WalletTransactions::Forbidden) do
      WalletTransactions::Transfer.call(
        actor: @actor, source_wallet: team_wallet, target_wallet: @source, amount: 1, idempotency_key: "team-debit"
      )
    end
  end

  test "transfer fails atomically if inserting the receiving ledger row fails" do
    WalletTransactions::Deposit.call(actor: @actor, target_wallet: @source, amount: 20, idempotency_key: "d1")
    connection = ActiveRecord::Base.connection
    connection.execute(<<~SQL)
      CREATE FUNCTION fail_test_receiver_entry() RETURNS trigger AS $$
      BEGIN
        IF NEW.wallet_id = #{@target.id} THEN
          RAISE EXCEPTION 'test receiver insert failure';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      CREATE TRIGGER zz_test_receiver_insert_failure
      BEFORE INSERT ON ledger_entries FOR EACH ROW EXECUTE FUNCTION fail_test_receiver_entry();
    SQL

    assert_raises(ActiveRecord::StatementInvalid) do
      WalletTransactions::Transfer.call(
        actor: @actor, source_wallet: @source, target_wallet: @target, amount: 5, idempotency_key: "atomic-failure"
      )
    end

    assert_equal BigDecimal("20"), @source.balance
    assert_equal BigDecimal("0"), @target.balance
    assert_not WalletTransaction.exists?(actor: @actor, idempotency_key: "atomic-failure")
  end

  test "transfers reject same-wallet requests and database prevents unsupported currencies" do
    assert_raises(WalletTransactions::InvalidRequest) do
      WalletTransactions::Transfer.call(
        actor: @actor, source_wallet: @source, target_wallet: @source, amount: 1, idempotency_key: "same"
      )
    end
    assert_raises(ActiveRecord::StatementInvalid) { @target.update_column(:currency, "USD") }
  end
end
