class CreateWalletOwners < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.timestamps
    end
    add_index :users, :email, unique: true

    create_table :teams do |t|
      t.string :name, null: false
      t.timestamps
    end

    create_table :stocks do |t|
      t.string :symbol, null: false
      t.timestamps
    end
    add_index :stocks, :symbol, unique: true
  end
end
