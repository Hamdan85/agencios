class AddPostgateGroupIdToClients < ActiveRecord::Migration[8.1]
  def change
    # PostGate profile-group id for this client's connected accounts (aggregator
    # routing — see connection_source on SocialAccount). Nil for a client whose
    # accounts are all direct-vendor.
    add_column :clients, :postgate_group_id, :string
    add_index :clients, :postgate_group_id
  end
end
