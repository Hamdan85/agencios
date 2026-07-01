# frozen_string_literal: true

# TikTok-specific columns on social_accounts (per docs/integrations/tiktok.md §5.2).
# Existing columns reused: external_user_id (= TikTok open_id), user_access_token,
# refresh_token, token_expires_at (= access_token_expires_at), scopes.
# These add what the doc requires beyond the shared shape.
class AddTiktokColumnsToSocialAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :social_accounts, :union_id, :string                  # TikTok union_id (stable across apps)
    add_column :social_accounts, :display_name, :string              # creator display name
    add_column :social_accounts, :avatar_url, :string                # creator avatar (note: TikTok 6h TTL)
    add_column :social_accounts, :refresh_token_expires_at, :datetime # TikTok refresh window (~365d)
    add_column :social_accounts, :revoked_at, :datetime # set on authorization.removed webhook
  end
end
