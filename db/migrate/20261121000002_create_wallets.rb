class CreateWallets < ActiveRecord::Migration[8.1]
  def change
    create_table :wallets do |t|
      t.references :owner, polymorphic: true, null: false, index: false
      t.string :currency, null: false, default: "IDR"
      t.timestamps
    end

    add_index :wallets, %i[owner_type owner_id currency], unique: true,
      name: "idx_wallets_owner_currency_unique"
    add_check_constraint :wallets, "currency = 'IDR'", name: "wallet_currency_is_idr"
  end
end
