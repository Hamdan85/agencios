# frozen_string_literal: true

class AddNameAndClientToCreatives < ActiveRecord::Migration[8.1]
  def change
    add_column :creatives, :name, :string
    add_reference :creatives, :client, null: true, foreign_key: true
  end
end
