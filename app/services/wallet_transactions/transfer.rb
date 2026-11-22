module WalletTransactions
  class Transfer < BaseOperation
    def call
      execute(transaction_type: "transfer", source: source_wallet, target: target_wallet)
    end
  end
end
