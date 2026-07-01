# frozen_string_literal: true

module Publishers
  # The single interface for publishing a Post. Every network is integrated
  # directly (full control + deeper analytics + no per-post markup) — callers
  # never branch on provider.
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
      'x' => %w[image carousel video text]
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

    def self.publish(post) = new(post).publish
    def self.sync(post)    = new(post).sync

    # The vendor module for a provider.
    def self.vendor_for(provider, workspace: nil)
      const_name = DIRECT.fetch(provider.to_s) { raise Vendors::Base::Error, "Rede não suportada: #{provider}" }
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

    private

    def actions
      self.class.vendor_for(@post.social_account.provider)::Actions
    end
  end
end
