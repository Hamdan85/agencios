# frozen_string_literal: true

module Publishers
  # The single interface for publishing a Post. Routes per-account, per
  # SocialAccount#connection_source:
  #   - `direct` accounts ride today's per-network vendor pipeline (Vendors::Meta,
  #     Vendors::TikTok, …) — fully untouched, rollback-safe.
  #   - `postgate` accounts route through the PostGate aggregator
  #     (Vendors::Postgate::Actions), which covers every network `DIRECT` doesn't
  #     (Pinterest, Bluesky, Mastodon, Telegram, Google Business) plus any direct
  #     network the workspace chose to connect via PostGate instead.
  # Callers never branch on provider or connection_source — this seam does.
  class SocialPublisher
    DIRECT = {
      'instagram' => 'Vendors::Meta',
      'facebook' => 'Vendors::Meta',
      'threads' => 'Vendors::Threads',
      'tiktok' => 'Vendors::TikTok',
      'youtube' => 'Vendors::Youtube',
      'linkedin' => 'Vendors::Linkedin',
      'x' => 'Vendors::X'
    }.freeze

    # OAuth connect routing: which slug a network authenticates through, and the
    # vendor for a slug. Slugs match the network name. Instagram connects via
    # Instagram Login (no Facebook Page / Business Manager — the easy path for
    # non-technical clients); Facebook via the Meta Facebook-Login app; Threads
    # via the Threads API. All three live in one Meta app.
    CONNECT_SLUG = {
      'instagram' => 'instagram', 'facebook' => 'facebook', 'threads' => 'threads',
      'tiktok' => 'tiktok', 'youtube' => 'youtube', 'linkedin' => 'linkedin', 'x' => 'x'
    }.freeze
    SLUG_VENDOR = {
      'facebook' => 'Vendors::Meta', 'instagram' => 'Vendors::InstagramLogin',
      'threads' => 'Vendors::Threads', 'tiktok' => 'Vendors::TikTok',
      'youtube' => 'Vendors::Youtube', 'linkedin' => 'Vendors::Linkedin', 'x' => 'Vendors::X'
    }.freeze

    # Media kinds each network can publish (Creative#media_kind). A creative whose
    # kind isn't supported is never posted to that network — e.g. TikTok / YouTube
    # are video-only, so an image creative skips them.
    SUPPORTED_MEDIA = {
      'instagram' => %w[image carousel video],
      'facebook' => %w[image carousel video text],
      'threads' => %w[image carousel video text],
      'tiktok' => %w[video],
      'youtube' => %w[video],
      'linkedin' => %w[image carousel video text],
      'x' => %w[image carousel video text],
      'pinterest' => %w[image video],
      'bluesky' => %w[image carousel text],
      'mastodon' => %w[image carousel video text],
      'telegram' => %w[image carousel video text],
      'google_business' => %w[image text]
    }.freeze

    # Providers where a still image can ride a video post as its cover/thumbnail
    # (Instagram Reels cover_url; YouTube thumbnails.set). On every other network a
    # cover image is just a normal image post. See Operations::Tickets::Publish.
    THUMBNAIL_CAPABLE = %w[instagram youtube].freeze

    # Whether `provider` can publish a creative of the given media kind.
    def self.supports?(provider, media_kind)
      kinds = SUPPORTED_MEDIA[provider.to_s]
      kinds.nil? || kinds.include?(media_kind.to_s)
    end

    # Whether a still cover image can be attached to a video post on `provider`.
    def self.thumbnail_capable?(provider)
      THUMBNAIL_CAPABLE.include?(provider.to_s)
    end

    def self.publish(post)   = new(post).publish
    def self.sync(post)      = new(post).sync
    def self.unpublish(post) = new(post).unpublish

    # The direct vendor module for a provider. Raises for any provider that has
    # no DIRECT entry (postgate-only networks, or a direct network reached
    # through a postgate-sourced account — see #actions, the routing entrypoint
    # that actually decides direct vs. postgate per account).
    def self.vendor_for(provider, workspace: nil)
      const_name = DIRECT.fetch(provider.to_s) do
        raise Vendors::Base::Error, I18n.t('vendors.social_publisher.unsupported_network', provider: provider)
      end
      const_name.constantize
    end

    def self.connect_slug(network) = CONNECT_SLUG[network.to_s]

    def self.vendor_for_slug(slug) = SLUG_VENDOR.fetch(slug.to_s) do
      raise Vendors::Base::Error, "Slug inválido: #{slug}"
    end.constantize

    def initialize(post)
      @post = post
    end

    def publish
      actions::PublishPost.call(@post)
    end

    def sync
      actions::SyncInsights.call(@post)
    end

    # Deletes the post from the network. Raises Vendors::Base::NotSupportedError
    # when the network's API has no delete endpoint (Instagram, Threads, TikTok).
    def unpublish
      actions::DeletePost.call(@post)
    end

    private

    # The Actions namespace this post's account publishes/syncs/deletes through:
    # PostGate for a postgate-sourced account (any network), the direct vendor
    # otherwise. New (postgate-only) networks have no DIRECT entry — they can
    # only ever reach here via a postgate-sourced account.
    def actions
      social_account = @post.social_account
      return Vendors::Postgate::Actions if social_account.connection_source_postgate?

      self.class.vendor_for(social_account.provider)::Actions
    end
  end
end
