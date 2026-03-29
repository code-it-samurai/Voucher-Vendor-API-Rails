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

ActiveRecord::Schema[8.1].define(version: 2026_03_27_084335) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.string "api_key", null: false
    t.decimal "balance", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.integer "lock_version", default: 0, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key"], name: "index_accounts_on_api_key", unique: true
    t.index ["email"], name: "index_accounts_on_email", unique: true
  end

  create_table "orders", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.decimal "denomination", precision: 10, scale: 2, null: false
    t.text "failure_reason"
    t.datetime "processed_at"
    t.bigint "product_id", null: false
    t.integer "quantity", default: 1, null: false
    t.string "reference_code", null: false
    t.string "status", default: "pending", null: false
    t.decimal "total_amount", precision: 12, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "idx_orders_account_status"
    t.index ["account_id"], name: "index_orders_on_account_id"
    t.index ["product_id"], name: "index_orders_on_product_id"
    t.index ["reference_code"], name: "index_orders_on_reference_code", unique: true
    t.index ["status"], name: "index_orders_on_status"
  end

  create_table "products", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "INR", null: false
    t.decimal "denomination", precision: 10, scale: 2, null: false
    t.string "name", null: false
    t.integer "stock", default: 0, null: false
    t.string "test_behavior"
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_products_on_active"
  end

  create_table "transaction_records", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.decimal "balance_after", precision: 12, scale: 2, null: false
    t.decimal "balance_before", precision: 12, scale: 2, null: false
    t.datetime "created_at", null: false
    t.bigint "order_id"
    t.string "transaction_type", null: false
    t.index ["account_id", "transaction_type"], name: "idx_txn_account_type"
    t.index ["account_id"], name: "index_transaction_records_on_account_id"
    t.index ["order_id"], name: "index_transaction_records_on_order_id"
    t.index ["transaction_type"], name: "index_transaction_records_on_transaction_type"
  end

  create_table "vouchers", force: :cascade do |t|
    t.string "claim_url"
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.bigint "order_id", null: false
    t.string "pin"
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_vouchers_on_code", unique: true
    t.index ["order_id"], name: "index_vouchers_on_order_id"
  end

  add_foreign_key "orders", "accounts"
  add_foreign_key "orders", "products"
  add_foreign_key "transaction_records", "accounts"
  add_foreign_key "transaction_records", "orders"
  add_foreign_key "vouchers", "orders"
end
