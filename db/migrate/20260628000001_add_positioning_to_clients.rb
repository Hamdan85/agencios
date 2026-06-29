# frozen_string_literal: true

class AddPositioningToClients < ActiveRecord::Migration[8.1]
  def change
    add_column :clients, :positioning, :jsonb, null: false, default: {}
  end
end
