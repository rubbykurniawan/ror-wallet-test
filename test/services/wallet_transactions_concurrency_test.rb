require "test_helper"

class WalletTransactionsConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @actor = User.create!(email: "concurrent@example.test", password: "correct horse battery staple")
    @receiver = User.create!(email: "receiver@example.test", password: "correct horse battery staple")
    @wallet = Wallet.create!(owner: @actor, currency: "IDR")
    @target = Wallet.create!(owner: @receiver, currency: "IDR")
  end

  teardown do
    ActiveRecord::Base.connection.execute(<<~SQL)
      TRUNCATE ledger_entries, wallet_transactions, user_sessions, wallets, users, teams, stocks
      RESTART IDENTITY CASCADE
    SQL
  end

  test "concurrent withdrawals cannot overspend a wallet" do
    WalletTransactions::Deposit.call(actor: @actor, target_wallet: @wallet, amount: 100, idempotency_key: "seed")
    outcomes = concurrent_calls(2) do |index|
      WalletTransactions::Withdrawal.call(
        actor: User.find(@actor.id), source_wallet: Wallet.find(@wallet.id), amount: 80,
        idempotency_key: "withdraw-#{index}"
      )
    end

    assert_equal 1, outcomes.count { |outcome| outcome.is_a?(WalletTransaction) }
    assert_equal 1, outcomes.count { |outcome| outcome == WalletTransactions::InsufficientFunds }
    assert_equal 2, @last_backend_pids.uniq.size
    assert_equal BigDecimal("20"), Wallet.find(@wallet.id).balance
    assert_equal 2, WalletTransaction.count
    assert_equal BigDecimal("20"), LedgerEntry.where(wallet_id: @wallet.id).sum(:amount)
  end

  test "concurrent duplicate keys create one transaction and one ledger entry" do
    outcomes = concurrent_calls(2) do
      WalletTransactions::Deposit.call(
        actor: User.find(@actor.id), target_wallet: Wallet.find(@wallet.id), amount: 25,
        idempotency_key: "concurrent-idempotency"
      )
    end

    assert_equal 1, outcomes.map(&:id).uniq.size
    assert_equal 2, @last_backend_pids.uniq.size
    assert_equal 1, WalletTransaction.count
    assert_equal 1, LedgerEntry.count
    assert_equal BigDecimal("25"), Wallet.find(@wallet.id).balance
  end

  private

  def concurrent_calls(count, &block)
    ready = Queue.new
    start = Queue.new
    backend_pids = Queue.new
    threads = count.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          backend_pids << ActiveRecord::Base.connection.select_value("SELECT pg_backend_pid()")
          ready << true
          start.pop
          begin
            block.call(index)
          rescue WalletTransactions::InsufficientFunds
            WalletTransactions::InsufficientFunds
          end
        end
      end
    end
    count.times { ready.pop }
    count.times { start << true }
    outcomes = threads.map(&:value)
    @last_backend_pids = count.times.map { backend_pids.pop }
    outcomes
  end
end
