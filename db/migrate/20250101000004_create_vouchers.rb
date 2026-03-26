class CreateVouchers < ActiveRecord::Migration[8.0]
  def change
    create_table :vouchers do |t|
      t.references :order, null: false, foreign_key: true
      t.string :code, null: false
      t.string :pin
      t.string :claim_url
      t.datetime :expires_at

      t.timestamps
    end

    add_index :vouchers, :code, unique: true
  end
end
