# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_21_000006) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "ledger_entries", force: :cascade do |t|
    t.bigint "wallet_id", null: false
    t.bigint "wallet_transaction_id", null: false
    t.decimal "amount", precision: 20, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["wallet_id"], name: "index_ledger_entries_on_wallet_id"
    t.index ["wallet_transaction_id", "wallet_id"], name: "idx_ledger_entries_transaction_wallet_unique", unique: true
    t.index ["wallet_transaction_id"], name: "index_ledger_entries_on_wallet_transaction_id"
    t.check_constraint "amount <> 0::numeric", name: "ledger_entry_amount_nonzero"
  end

  create_table "stocks", force: :cascade do |t|
    t.string "symbol", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["symbol"], name: "index_stocks_on_symbol", unique: true
  end

  create_table "teams", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "user_sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "token_digest", limit: 64, null: false
    t.string "csrf_token_digest", limit: 64, null: false
    t.datetime "expires_at", null: false
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token_digest"], name: "index_user_sessions_on_token_digest", unique: true
    t.index ["user_id"], name: "index_user_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "wallet_transactions", force: :cascade do |t|
    t.string "transaction_type", null: false
    t.bigint "actor_id", null: false
    t.bigint "source_wallet_id"
    t.bigint "target_wallet_id"
    t.decimal "amount", precision: 20, scale: 2, null: false
    t.string "idempotency_key", null: false
    t.string "request_fingerprint", limit: 64, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id", "idempotency_key"], name: "idx_wallet_transactions_actor_idempotency_unique", unique: true
    t.index ["actor_id"], name: "index_wallet_transactions_on_actor_id"
    t.index ["source_wallet_id"], name: "index_wallet_transactions_on_source_wallet_id"
    t.index ["target_wallet_id"], name: "index_wallet_transactions_on_target_wallet_id"
    t.check_constraint "amount > 0::numeric", name: "wallet_transaction_amount_positive"
    t.check_constraint "transaction_type::text = 'deposit'::text AND source_wallet_id IS NULL AND target_wallet_id IS NOT NULL OR transaction_type::text = 'withdraw'::text AND source_wallet_id IS NOT NULL AND target_wallet_id IS NULL OR transaction_type::text = 'transfer'::text AND source_wallet_id IS NOT NULL AND target_wallet_id IS NOT NULL AND source_wallet_id <> target_wallet_id", name: "wallet_transaction_wallet_direction_valid"
    t.check_constraint "transaction_type::text = ANY (ARRAY['deposit'::character varying::text, 'withdraw'::character varying::text, 'transfer'::character varying::text])", name: "wallet_transaction_type_valid"
  end

  create_table "wallets", force: :cascade do |t|
    t.string "owner_type", null: false
    t.bigint "owner_id", null: false
    t.string "currency", default: "IDR", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id", "currency"], name: "idx_wallets_owner_currency_unique", unique: true
    t.check_constraint "currency::text = 'IDR'::text", name: "wallet_currency_is_idr"
  end

  add_foreign_key "ledger_entries", "wallet_transactions"
  add_foreign_key "ledger_entries", "wallets"
  add_foreign_key "user_sessions", "users", on_delete: :restrict
  add_foreign_key "wallet_transactions", "users", column: "actor_id"
  add_foreign_key "wallet_transactions", "wallets", column: "source_wallet_id"
  add_foreign_key "wallet_transactions", "wallets", column: "target_wallet_id"
end
