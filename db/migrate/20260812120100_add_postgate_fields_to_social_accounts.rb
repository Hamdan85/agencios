class AddPostgateFieldsToSocialAccounts < ActiveRecord::Migration[8.1]
  def change
    # Which transport publishes/tracks this account: `direct` (today's per-network
    # vendor pipeline, untouched) or `postgate` (routed through the PostGate
    # aggregator). Default `direct` so every existing row is unaffected.
    add_column :social_accounts, :connection_source, :integer, null: false, default: 0
    add_column :social_accounts, :postgate_profile_id, :string
    add_index :social_accounts, :postgate_profile_id
    # Per-account PostGate extras (e.g. Pinterest default board_id). Never
    # ransackable — mirrors why token columns are excluded from the admin panel.
    add_column :social_accounts, :postgate_meta, :jsonb, null: false, default: {}
  end
end
