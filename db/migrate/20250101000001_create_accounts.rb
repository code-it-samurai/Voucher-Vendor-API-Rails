class CreateAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :accounts do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :api_key, null: false
      t.decimal :balance, null: false, default: 0.0, precision: 12, scale: 2
      t.integer :lock_version, null: false, default: 0

      t.timestamps
    end

    add_index :accounts, :email, unique: true
    add_index :accounts, :api_key, unique: true
  end
end
