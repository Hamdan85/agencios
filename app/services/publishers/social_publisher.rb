# frozen_string_literal: true

module Publishers
  # The single interface for publishing a Post. Every network is integrated
  # directly (full control + deeper analytics + no per-post markup) — callers
  # never branch on provider.
  class SocialPublisher
    DIRECT = {
      "instagram" => "Vendors::Meta",
      "facebook"  => "Vendors::Meta",
      "threads"   => "Vendors::Threads",
      "tiktok"    => "Vendors::TikTok",
      "youtube"   => "Vendors::Youtube",
      "linkedin"  => "Vendors::Linkedin",
      "x"         => "Vendors::X",
    }.freeze

    # OAuth connect routing: which slug a network authenticates through, and the
    # vendor for a slug. Slugs match the network name. Instagram connects via
    # Instagram Login (no Facebook Page / Business Manager — the easy path for
    # non-technical clients); Facebook via the Meta Facebook-Login app; Threads
    # via the Threads API. All three live in one Meta app.
    CONNECT_SLUG = {
      "instagram" => "instagram", "facebook" => "facebook", "threads" => "threads",
      "tiktok" => "tiktok", "youtube" => "youtube", "linkedin" => "linkedin", "x" => "x",
    }.freeze
    SLUG_VENDOR = {
      "facebook" => "Vendors::Meta", "instagram" => "Vendors::InstagramLogin",
      "threads" => "Vendors::Threads", "tiktok" => "Vendors::TikTok",
      "youtube" => "Vendors::Youtube", "linkedin" => "Vendors::Linkedin", "x" => "Vendors::X",
    }.freeze

    def self.publish(post) = new(post).publish
    def self.sync(post)    = new(post).sync

    # The vendor module for a provider.
    def self.vendor_for(provider, workspace: nil)
      const_name = DIRECT.fetch(provider.to_s) { raise Vendors::Base::Error, "Rede não suportada: #{provider}" }
      const_name.constantize
    end

    def self.connect_slug(network) = CONNECT_SLUG[network.to_s]
    def self.vendor_for_slug(slug) = SLUG_VENDOR.fetch(slug.to_s) { raise Vendors::Base::Error, "Slug inválido: #{slug}" }.constantize

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
