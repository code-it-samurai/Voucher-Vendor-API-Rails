class CreateProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :products do |t|
      t.string :name, null: false
      t.decimal :denomination, null: false, precision: 10, scale: 2
      t.string :currency, null: false, default: "INR"
      t.boolean :active, null: false, default: true
      t.integer :stock, null: false, default: 0
      t.string :test_behavior

      t.timestamps
    end
  end
end
