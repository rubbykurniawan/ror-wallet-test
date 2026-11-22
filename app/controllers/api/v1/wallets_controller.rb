module Api
  module V1
    class WalletsController < BaseController
      def show
        wallet = Wallet.find(params[:id])
        authorize_read!(wallet)
        render json: { data: wallet_data(wallet) }
      end

      def transactions
        wallet = Wallet.find(params[:id])
        authorize_read!(wallet)
        entries = wallet.ledger_entries.includes(:wallet_transaction).order(id: :desc).limit(100)
        render json: {
          data: entries.map do |entry|
            {
              id: entry.id,
              transaction_id: entry.wallet_transaction_id,
              type: entry.wallet_transaction.transaction_type,
              amount: money(entry.amount),
              created_at: entry.created_at.iso8601
            }
          end
        }
      end

      private

      def wallet_data(wallet)
        { id: wallet.id, currency: wallet.currency, balance: money(wallet.balance) }
      end
    end
  end
end
