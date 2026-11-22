class CreateLedgerEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :ledger_entries do |t|
      t.references :wallet, null: false, foreign_key: true
      t.references :wallet_transaction, null: false, foreign_key: true
      t.decimal :amount, precision: 20, scale: 2, null: false
      t.timestamps
    end

    add_index :ledger_entries, %i[wallet_transaction_id wallet_id], unique: true,
      name: "idx_ledger_entries_transaction_wallet_unique"
    add_check_constraint :ledger_entries, "amount <> 0", name: "ledger_entry_amount_nonzero"
  end
end
