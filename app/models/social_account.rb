# frozen_string_literal: true

# One row per connected network per CLIENT. The agency (workspace) connects each
# of its clients' own social networks; the tickets under that client's projects
# publish to them. `workspace_id` is kept for tenant scoping. OAuth tokens encrypted.
#
# `connection_source` decides the publish/insights transport: `direct` accounts
# ride today's per-network vendor pipeline (Vendors::Meta, Vendors::TikTok, …);
# `postgate` accounts route through the PostGate aggregator
# (Vendors::Postgate::Actions) via `postgate_profile_id`. See
# Publishers::SocialPublisher.
class SocialAccount < ApplicationRecord
  belongs_to :workspace
  belongs_to :client
  has_many :posts, dependent: :nullify
  has_many :account_metrics, dependent: :destroy

  # Direct networks integrate one-to-one (no aggregator); postgate-sourced
  # accounts (any platform PostGate supports) also carry one of these values so
  # publishing/media-support checks stay provider-shaped. Integer values are
  # stable/historical — `6` is intentionally retired and left unused.
  enum :provider, {
    instagram: 0, facebook: 1, tiktok: 2, youtube: 3, linkedin: 4, x: 5,
    threads: 7, pinterest: 8, bluesky: 9, mastodon: 10, telegram: 11, google_business: 12
  }, prefix: true

  enum :status, { connected: 0, needs_reauth: 1, revoked: 2 }, prefix: true

  # How the account authenticated, which decides the publish/insights transport:
  # `facebook_login` → Page token on graph.facebook.com (IG via a linked Page,
  # plus all Facebook Pages); `instagram_login` → IG user token on
  # graph.instagram.com (Instagram-only, no Facebook Page required).
  enum :connection_type, { facebook_login: 0, instagram_login: 1 }, prefix: true

  # `direct` = today's per-network vendor pipeline (unchanged, rollback-safe);
  # `postgate` = routed through the PostGate aggregator. See
  # Publishers::SocialPublisher#actions.
  enum :connection_source, { direct: 0, postgate: 1 }, prefix: true

  encrypts :user_access_token, :page_access_token, :refresh_token

  def token_expired?
    token_expires_at.present? && token_expires_at.past?
  end

  # LGPD: token/secret columns are intentionally excluded so they can't be
  # searched or surfaced in the admin panel. `postgate_meta` is excluded too —
  # it may carry provider-side identifiers best kept out of the admin search UI.
  def self.ransackable_attributes(_auth = nil)
    %w[id workspace_id client_id provider username display_name status
       connection_type connection_source postgate_profile_id token_expires_at
       last_synced_at revoked_at created_at updated_at]
  end

  def self.ransackable_associations(_auth = nil)
    %w[workspace client posts]
  end
end
