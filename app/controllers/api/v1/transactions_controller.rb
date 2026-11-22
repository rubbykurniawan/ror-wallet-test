module Api
  module V1
    class TransactionsController < BaseController
      def deposit
        wallet = Wallet.find(params[:target_wallet_id])
        policy = WalletAccessPolicy.new(current_user)
        raise WalletTransactions::Forbidden, "deposit target is forbidden" unless policy.deposit?(wallet)

        transaction = WalletTransactions::Deposit.call(
          actor: current_user, target_wallet: wallet, amount: params[:amount], idempotency_key: idempotency_key
        )
        render_transaction(transaction, balance_wallet: wallet, status: :created)
      end

      def withdraw
        wallet = Wallet.find(params[:source_wallet_id])
        policy = WalletAccessPolicy.new(current_user)
        raise WalletTransactions::Forbidden, "source wallet is forbidden" unless policy.debit?(wallet)

        transaction = WalletTransactions::Withdrawal.call(
          actor: current_user, source_wallet: wallet, amount: params[:amount], idempotency_key: idempotency_key
        )
        render_transaction(transaction, balance_wallet: wallet, status: :created)
      end

      def transfer
        source = Wallet.find(params[:source_wallet_id])
        target = Wallet.find(params[:target_wallet_id])
        policy = WalletAccessPolicy.new(current_user)
        raise WalletTransactions::Forbidden, "source wallet is forbidden" unless policy.debit?(source)
        raise WalletTransactions::Forbidden, "transfer target is forbidden" unless policy.transfer_target?(target)

        transaction = WalletTransactions::Transfer.call(
          actor: current_user, source_wallet: source, target_wallet: target,
          amount: params[:amount], idempotency_key: idempotency_key
        )
        data = transaction_data(transaction)
        data[:data][:source_balance] = money(source.reload.balance)
        render json: data, status: :created
      end

      private

      def idempotency_key
        request.headers["Idempotency-Key"]
      end

      def render_transaction(transaction, balance_wallet:, status:)
        render json: transaction_data(transaction).tap { |data| data[:data][:balance] = money(balance_wallet.reload.balance) }, status: status
      end

      def transaction_data(transaction)
        {
          data: {
            id: transaction.id,
            type: transaction.transaction_type,
            amount: format("%.2f", transaction.amount),
            source_wallet_id: transaction.source_wallet_id,
            target_wallet_id: transaction.target_wallet_id,
            ledger_entries: transaction.ledger_entries.order(:id).map do |entry|
              { wallet_id: entry.wallet_id, amount: format("%.2f", entry.amount) }
            end
          }
        }
      end
    end
  end
end
