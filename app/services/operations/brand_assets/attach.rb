# frozen_string_literal: true

module Operations
  module BrandAssets
    # Attaches/replaces an owner's brand assets. The owner is any model exposing
    # `has_one_attached :logo` + `:default_creator_avatar` (Client, Workspace).
    # Each asset is optional — only the ones present in the call are (re)attached.
    # `carousel_background` is only meaningful on Client (the image carousel style).
    class Attach < Operations::Base
      def initialize(owner:, logo: nil, default_creator_avatar: nil, carousel_background: nil)
        @owner = owner
        @logo = logo
        @avatar = default_creator_avatar
        @carousel_background = carousel_background
      end

      def call
        @owner.logo.attach(@logo) if @logo.present?
        @owner.default_creator_avatar.attach(@avatar) if @avatar.present?
        if @carousel_background.present? && @owner.respond_to?(:carousel_background)
          @owner.carousel_background.attach(@carousel_background)
          # Re-derive the image-style palette from the new background (async — the
          # vision call must not block this upload). Idempotent on the blob checksum.
          ::Creatives::DeriveCarouselPaletteJob.perform_later(@owner.id) if @owner.is_a?(Client)
        end
        @owner
      end
    end
  end
end
