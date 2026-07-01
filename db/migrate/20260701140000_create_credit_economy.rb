# frozen_string_literal: true

class CreateCreditEconomy < ActiveRecord::Migration[8.1]
  def change
    # Founding-user comp: bypasses the billing paywall and seat limit entirely.
    add_column :workspaces, :godfathered, :boolean, null: false, default: false

    # Whether a valid payment method is on file. The trial only grants access
    # once a card has been added (card-required trial).
    add_column :subscriptions, :card_on_file, :boolean, null: false, default: false

    # One prepaid credit wallet per workspace. `granted_balance` is the monthly
    # plan allotment (expires at period end); `purchased_balance` is topped-up
    # credits (roll over up to 12 months). Balance columns are the authoritative
    # cache; credit_transactions is the append-only audit trail.
    create_table :credit_wallets do |t|
      t.references :workspace, null: false, foreign_key: true, index: { unique: true }
      t.integer  :granted_balance,   null: false, default: 0
      t.integer  :purchased_balance, null: false, default: 0
      t.datetime :granted_expires_at
      t.timestamps
    end

    create_table :credit_transactions do |t|
      t.references :workspace,  null: false, foreign_key: true
      t.references :generation, null: true,  foreign_key: true
      t.references :user,       null: true,  foreign_key: true
      # grant | purchase | debit | refund | expire | adjustment
      t.string   :kind,   null: false
      # bucket touched: granted | purchased | mixed
      t.string   :bucket, null: false, default: 'purchased'
      t.integer  :amount, null: false # signed (+ credit, − debit)
      t.integer  :granted_delta,   null: false, default: 0
      t.integer  :purchased_delta, null: false, default: 0
      t.integer  :balance_after,   null: false, default: 0
      t.datetime :expires_at
      t.string   :description
      t.jsonb    :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :credit_transactions, %i[workspace_id created_at]
    add_index :credit_transactions, %i[kind created_at]
  end
end
