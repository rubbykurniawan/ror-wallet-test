module WalletTransactions
  class Withdrawal < BaseOperation
    def call
      execute(transaction_type: "withdraw", source: source_wallet, target: nil)
    end
  end
end
