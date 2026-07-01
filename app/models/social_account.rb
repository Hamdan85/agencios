# frozen_string_literal: true

# One row per connected network per CLIENT. The agency (workspace) connects each
# of its clients' own social networks; the tickets under that client's projects
# publish to them. `workspace_id` is kept for tenant scoping. OAuth tokens encrypted.
class SocialAccount < ApplicationRecord
  belongs_to :workspace
  belongs_to :client
  has_many :posts, dependent: :nullify
  has_many :account_metrics, dependent: :destroy

  # Networks integrate directly by default; `upload_post` is the aggregator
  # fallback provider (publisher seam routes to it per workspace/network).
  enum :provider, {
    instagram: 0, facebook: 1, tiktok: 2, youtube: 3, linkedin: 4, x: 5, upload_post: 6,
    threads: 7
  }, prefix: true

  enum :status, { connected: 0, needs_reauth: 1, revoked: 2 }, prefix: true

  # How the account authenticated, which decides the publish/insights transport:
  # `facebook_login` → Page token on graph.facebook.com (IG via a linked Page,
  # plus all Facebook Pages); `instagram_login` → IG user token on
  # graph.instagram.com (Instagram-only, no Facebook Page required).
  enum :connection_type, { facebook_login: 0, instagram_login: 1 }, prefix: true

  encrypts :user_access_token, :page_access_token, :refresh_token

  def token_expired?
    token_expires_at.present? && token_expires_at.past?
  end

  # LGPD: token/secret columns are intentionally excluded so they can't be
  # searched or surfaced in the admin panel.
  def self.ransackable_attributes(_auth = nil)
    %w[id workspace_id client_id provider username display_name status
       connection_type token_expires_at last_synced_at revoked_at created_at updated_at]
  end

  def self.ransackable_associations(_auth = nil)
    %w[workspace client posts]
  end
end
