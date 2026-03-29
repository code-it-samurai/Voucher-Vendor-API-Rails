class AddNotesToTransactionRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :transaction_records, :notes, :text
  end
end
