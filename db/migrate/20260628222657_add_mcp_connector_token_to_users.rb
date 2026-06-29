# frozen_string_literal: true

class AddMcpConnectorTokenToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :mcp_connector_token, :string
    add_index :users, :mcp_connector_token, unique: true
  end
end
