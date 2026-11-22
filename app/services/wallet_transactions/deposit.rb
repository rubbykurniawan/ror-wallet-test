module WalletTransactions
  class Deposit < BaseOperation
    def call
      execute(transaction_type: "deposit", source: nil, target: target_wallet)
    end
  end
end
