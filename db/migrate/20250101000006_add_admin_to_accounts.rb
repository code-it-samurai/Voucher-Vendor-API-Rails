class AddAdminToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :admin, :boolean, default: false, null: false
  end
end
