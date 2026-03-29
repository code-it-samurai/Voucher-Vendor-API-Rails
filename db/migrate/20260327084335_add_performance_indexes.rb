class AddPerformanceIndexes < ActiveRecord::Migration[8.1]
  def change
    # Product catalog lookups filter by active status
    add_index :products, :active

    # Transaction history queries filter by account + type
    add_index :transaction_records, [:account_id, :transaction_type], name: "idx_txn_account_type"

    # Order lookups by account + status (e.g. "my pending orders")
    add_index :orders, [:account_id, :status], name: "idx_orders_account_status"
  end
end
