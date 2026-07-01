# frozen_string_literal: true

class AddOverSeatLimitToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :over_seat_limit, :boolean, null: false, default: false
  end
end
