# frozen_string_literal: true

# One row per connected network per CLIENT. The agency (workspace) connects each
# of its clients' own social networks; the tickets under that client's projects
# publish to them. `workspace_id` is kept for tenant scoping. OAuth tokens encrypted.
class SocialAccount < ApplicationRecord
  belongs_to :workspace
  belongs_to :client
  has_many :posts, dependent: :nullify

  # Networks integrate directly by default; `upload_post` is the aggregator
  # fallback provider (publisher seam routes to it per workspace/network).
  enum :provider, {
    instagram: 0, facebook: 1, tiktok: 2, youtube: 3, linkedin: 4, x: 5, upload_post: 6
  }, prefix: true

  enum :status, { connected: 0, needs_reauth: 1, revoked: 2 }, prefix: true

  encrypts :user_access_token, :page_access_token, :refresh_token

  def token_expired?
    token_expires_at.present? && token_expires_at.past?
  end
end
