class CreateWalletTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :wallet_transactions do |t|
      t.string :transaction_type, null: false
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.references :source_wallet, null: true, foreign_key: { to_table: :wallets }
      t.references :target_wallet, null: true, foreign_key: { to_table: :wallets }
      t.decimal :amount, precision: 20, scale: 2, null: false
      t.string :idempotency_key, null: false
      t.string :request_fingerprint, null: false, limit: 64
      t.timestamps
    end

    add_index :wallet_transactions, %i[actor_id idempotency_key], unique: true,
      name: "idx_wallet_transactions_actor_idempotency_unique"
    add_check_constraint :wallet_transactions, "amount > 0",
      name: "wallet_transaction_amount_positive"
    add_check_constraint :wallet_transactions,
      "transaction_type IN ('deposit', 'withdraw', 'transfer')",
      name: "wallet_transaction_type_valid"
    add_check_constraint :wallet_transactions, <<~SQL.squish,
      (transaction_type = 'deposit' AND source_wallet_id IS NULL AND target_wallet_id IS NOT NULL)
      OR (transaction_type = 'withdraw' AND source_wallet_id IS NOT NULL AND target_wallet_id IS NULL)
      OR (transaction_type = 'transfer' AND source_wallet_id IS NOT NULL AND target_wallet_id IS NOT NULL AND source_wallet_id <> target_wallet_id)
    SQL
      name: "wallet_transaction_wallet_direction_valid"
  end
end
