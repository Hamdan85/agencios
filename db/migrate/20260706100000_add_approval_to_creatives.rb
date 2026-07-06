# frozen_string_literal: true

class AddApprovalToCreatives < ActiveRecord::Migration[8.1]
  def change
    add_column :creatives, :approval_state, :string, null: false, default: 'pending'
    add_column :creatives, :client_feedback, :text
    add_column :creatives, :decided_at, :datetime
    # Who decided — a workspace User (internal "Aprovar") or the Client (via link).
    add_reference :creatives, :reviewed_by, polymorphic: true, null: true, index: true
  end
end
