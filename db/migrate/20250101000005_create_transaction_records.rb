class CreateTransactionRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :transaction_records do |t|
      t.references :account, null: false, foreign_key: true
      t.references :order, foreign_key: true
      t.string :transaction_type, null: false
      t.decimal :amount, null: false, precision: 12, scale: 2
      t.decimal :balance_before, null: false, precision: 12, scale: 2
      t.decimal :balance_after, null: false, precision: 12, scale: 2

      t.datetime :created_at, null: false
    end

    add_index :transaction_records, :transaction_type
  end
end
