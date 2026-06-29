# frozen_string_literal: true

# YouTube-specific columns on social_accounts (per docs/integrations/youtube.md §5).
# Existing columns reused: channel_id (= external_channel_id, UC...), user_access_token
# (= access_token), refresh_token, token_expires_at, scopes, status.
# This adds the channel display name the doc resolves via channels.list?mine=true.
class AddYoutubeColumnsToSocialAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :social_accounts, :channel_title, :string # resolved from channels.list snippet.title
  end
end
