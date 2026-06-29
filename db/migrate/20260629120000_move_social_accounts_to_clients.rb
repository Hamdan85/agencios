# frozen_string_literal: true

# Social connections belong to the agency's CLIENTS, not the workspace itself.
# A workspace (the agency) connects each client's own Instagram/TikTok/etc., and
# the tickets under that client's projects publish to them. This moves the owning
# parent from `workspace` to `client` (workspace_id stays for tenant scoping).
class MoveSocialAccountsToClients < ActiveRecord::Migration[8.1]
  def up
    add_reference :social_accounts, :client, foreign_key: true, index: true

    # Backfill existing (workspace-scoped) accounts onto the workspace's first
    # client so the NOT NULL constraint can be applied. Accounts whose workspace
    # has no client are orphaned and removed along with their posts/metrics.
    execute <<~SQL.squish
      UPDATE social_accounts sa
      SET client_id = (
        SELECT c.id FROM clients c
        WHERE c.workspace_id = sa.workspace_id
        ORDER BY c.id ASC LIMIT 1
      )
    SQL

    execute <<~SQL.squish
      DELETE FROM post_metrics WHERE post_id IN (
        SELECT id FROM posts WHERE social_account_id IN (
          SELECT id FROM social_accounts WHERE client_id IS NULL
        )
      )
    SQL
    execute <<~SQL.squish
      DELETE FROM posts WHERE social_account_id IN (
        SELECT id FROM social_accounts WHERE client_id IS NULL
      )
    SQL
    execute "DELETE FROM social_accounts WHERE client_id IS NULL"

    change_column_null :social_accounts, :client_id, false
    add_index :social_accounts, %i[client_id provider]
  end

  def down
    remove_index :social_accounts, %i[client_id provider]
    remove_reference :social_accounts, :client, foreign_key: true
  end
end
