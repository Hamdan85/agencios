# frozen_string_literal: true

class CreateCrm < ActiveRecord::Migration[8.1]
  def change
    create_table :clients do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string  :name, null: false
      t.string  :company
      t.string  :email
      t.string  :phone
      t.string  :document
      t.text    :notes
      t.integer :status, null: false, default: 0
      t.jsonb   :attribution, null: false, default: {}
      t.timestamps
    end
    add_index :clients, %i[workspace_id status]

    create_table :projects do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.string  :name, null: false
      t.text    :description
      t.string  :color, null: false, default: '#7C3AED'
      t.integer :status, null: false, default: 0
      t.date    :starts_on
      t.date    :ends_on
      t.integer :budget_cents
      t.timestamps
    end
    add_index :projects, %i[workspace_id status]
  end
end
