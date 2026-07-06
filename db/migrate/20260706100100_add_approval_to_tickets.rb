# frozen_string_literal: true

class AddApprovalToTickets < ActiveRecord::Migration[8.1]
  def change
    add_column :tickets, :approval_token, :string
    add_column :tickets, :approval_requested_at, :datetime
    add_index  :tickets, :approval_token, unique: true
  end
end
