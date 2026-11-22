require "test_helper"

class WalletOwnerIntegrityTest < ActiveSupport::TestCase
  test "database rejects wallets with missing registered owners" do
    [ "User", "Team", "Stock" ].each do |owner_type|
      error = assert_raises(ActiveRecord::StatementInvalid) do
        Wallet.transaction(requires_new: true) do
          Wallet.insert_all!([
            {
              owner_type: owner_type,
              owner_id: -1,
              currency: "IDR",
              created_at: Time.current,
              updated_at: Time.current
            }
          ])
        end
      end

      assert_match "wallet owner does not exist", error.message
    end
  end

  test "database rejects unsupported wallet owner types" do
    error = assert_raises(ActiveRecord::StatementInvalid) do
      Wallet.transaction(requires_new: true) do
        Wallet.insert_all!([
          {
            owner_type: "UnknownOwner",
            owner_id: 1,
            currency: "IDR",
            created_at: Time.current,
            updated_at: Time.current
          }
        ])
      end
    end

    assert_match "wallet owner type is not supported", error.message
  end

  test "database rejects reassigning a wallet to a missing registered owner" do
    user = User.create!(email: "wallet-reassignment@example.test", password: "test-password")
    wallet = Wallet.create!(owner: user, currency: "IDR")

    [ "User", "Team", "Stock" ].each do |owner_type|
      error = assert_raises(ActiveRecord::StatementInvalid) do
        Wallet.transaction(requires_new: true) do
          Wallet.where(id: wallet.id).update_all(owner_type: owner_type, owner_id: -1)
        end
      end

      assert_match "wallet owner does not exist", error.message
    end
  end

  test "database prevents deleting or changing the id of an owner with a wallet" do
    owners = [
      User.create!(email: "wallet-owner@example.test", password: "test-password"),
      Team.create!(name: "Wallet Owner Team"),
      Stock.create!(symbol: "WOWN")
    ]

    owners.each do |owner|
      Wallet.create!(owner: owner, currency: "IDR")

      delete_error = assert_raises(ActiveRecord::StatementInvalid) do
        Wallet.transaction(requires_new: true) do
          owner.class.where(id: owner.id).delete_all
        end
      end
      assert_match "wallet owner is referenced by a wallet", delete_error.message

      update_error = assert_raises(ActiveRecord::StatementInvalid) do
        Wallet.transaction(requires_new: true) do
          owner.class.where(id: owner.id).update_all(id: owner.id + 10_000)
        end
      end
      assert_match "wallet owner is referenced by a wallet", update_error.message
    end
  end
end

class WalletOwnerIntegrityConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "owner deletion waits for concurrent wallet creation and then rejects it" do
    team = Team.create!(name: "Concurrent Delete Owner")
    result = assert_owner_change_waits_for_wallet_commit(team) do
      Team.where(id: team.id).delete_all
    end

    assert_kind_of ActiveRecord::StatementInvalid, result
    assert_match "wallet owner is referenced by a wallet", result.message
    assert Team.exists?(team.id)
    assert_equal 1, Wallet.where(owner: team).count
  ensure
    cleanup_owner(team)
  end

  test "owner id change waits for concurrent wallet creation and then rejects it" do
    team = Team.create!(name: "Concurrent Update Owner")
    replacement_id = team.id + 10_000
    result = assert_owner_change_waits_for_wallet_commit(team) do
      Team.where(id: team.id).update_all(id: replacement_id)
    end

    assert_kind_of ActiveRecord::StatementInvalid, result
    assert_match "wallet owner is referenced by a wallet", result.message
    assert Team.exists?(team.id)
    assert_not Team.exists?(replacement_id)
    assert_equal 1, Wallet.where(owner: team).count
  ensure
    cleanup_owner(team)
  end

  private

  def assert_owner_change_waits_for_wallet_commit(team)
    wallet_created = Queue.new
    commit_wallet = Queue.new
    change_backend_pid = Queue.new
    change_result = Queue.new

    wallet_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        ActiveRecord::Base.transaction do
          Wallet.create!(owner: Team.find(team.id), currency: "IDR")
          wallet_created << true
          commit_wallet.pop
        end
      end
    rescue StandardError => error
      wallet_created << error
    end

    wallet_created_result = wallet_created.pop
    raise wallet_created_result if wallet_created_result.is_a?(StandardError)

    owner_change_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        change_backend_pid << connection.select_value("SELECT pg_backend_pid()")
        begin
          yield
          change_result << :changed
        rescue StandardError => error
          change_result << error
        end
      end
    end

    backend_pid = change_backend_pid.pop
    wait_for_owner_change_lock(backend_pid)
    commit_wallet << true
    wallet_thread.join
    owner_change_thread.join

    change_result.pop
  ensure
    commit_wallet << true if wallet_thread&.alive?
    wallet_thread&.join(5)
    owner_change_thread&.join(5)
  end

  def wait_for_owner_change_lock(backend_pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5

    loop do
      wait_event_type = ActiveRecord::Base.connection.select_value(
        "SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(backend_pid)}"
      )
      return if wait_event_type == "Lock"

      raise "owner change did not wait for the wallet transaction" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.01
    end
  end

  def cleanup_owner(team)
    return unless team

    Wallet.where(owner_type: "Team", owner_id: team.id).delete_all
    Team.where(id: team.id).delete_all
  end
end
