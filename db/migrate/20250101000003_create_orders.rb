class CreateOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :orders do |t|
      t.string :reference_code, null: false
      t.references :account, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.integer :quantity, null: false, default: 1
      t.decimal :denomination, null: false, precision: 10, scale: 2
      t.decimal :total_amount, null: false, precision: 12, scale: 2
      t.string :status, null: false, default: "pending"
      t.text :failure_reason
      t.integer :attempts, null: false, default: 0
      t.datetime :processed_at
      t.datetime :cancelled_at

      t.timestamps
    end

    add_index :orders, :reference_code, unique: true
    add_index :orders, :status
  end
end
