class AddApprovalTokenToClients < ActiveRecord::Migration[8.1]
  def change
    add_column :clients, :approval_token, :string
    add_index :clients, :approval_token, unique: true
  end
end
