# frozen_string_literal: true

module Publishers
  # The single interface for publishing a Post. Every network is integrated
  # directly (full control + deeper analytics + no per-post markup) — callers
  # never branch on provider.
  class SocialPublisher
    DIRECT = {
      "instagram" => "Vendors::Meta",
      "facebook"  => "Vendors::Meta",
      "tiktok"    => "Vendors::TikTok",
      "youtube"   => "Vendors::Youtube",
      "linkedin"  => "Vendors::Linkedin",
      "x"         => "Vendors::X",
    }.freeze

    # OAuth connect routing: which app/slug a network authenticates through
    # (Instagram + Facebook share one Meta app), and the vendor for a slug.
    CONNECT_SLUG = {
      "instagram" => "meta", "facebook" => "meta", "tiktok" => "tiktok",
      "youtube" => "youtube", "linkedin" => "linkedin", "x" => "x",
    }.freeze
    SLUG_VENDOR = {
      "meta" => "Vendors::Meta", "tiktok" => "Vendors::TikTok", "youtube" => "Vendors::Youtube",
      "linkedin" => "Vendors::Linkedin", "x" => "Vendors::X",
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
