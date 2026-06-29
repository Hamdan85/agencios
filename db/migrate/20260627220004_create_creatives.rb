# frozen_string_literal: true

class CreateCreatives < ActiveRecord::Migration[8.1]
  def change
    create_table :creatives do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :ticket, foreign_key: true
      t.string   :creative_type, null: false
      t.integer  :source, null: false, default: 0
      t.integer  :status, null: false, default: 0
      t.string   :provider
      t.jsonb    :metadata, null: false, default: {}
      t.text     :caption
      t.integer  :version, null: false, default: 1
      t.references :parent, foreign_key: { to_table: :creatives }
      t.timestamps
    end
    add_index :creatives, %i[workspace_id status]

    create_table :generations do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :creative, foreign_key: true
      t.integer  :kind, null: false, default: 0
      t.integer  :status, null: false, default: 0
      t.string   :provider
      t.string   :external_id
      t.integer  :cost_cents
      t.datetime :metered_at
      t.jsonb    :params, null: false, default: {}
      t.jsonb    :result, null: false, default: {}
      t.string   :failure_reason
      t.timestamps
    end
    add_index :generations, %i[workspace_id kind status]
    add_index :generations, :external_id
  end
end
