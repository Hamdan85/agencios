# frozen_string_literal: true

module Operations
  module BrandAssets
    # Copies the first image of an existing platform creative into the owner's
    # `carousel_background`. Copies the bytes (independent blob) so a later purge
    # of the source creative can't delete the client's background.
    class AttachFromCreative < Operations::Base
      def initialize(owner:, creative:)
        @owner = owner
        @creative = creative
      end

      def call
        source = @creative.assets.attachments.find { |a| a.blob&.image? }
        raise Operations::Errors::Invalid, 'O criativo selecionado não tem imagem.' if source.nil?

        @owner.carousel_background.attach(
          io: StringIO.new(source.download),
          filename: source.filename.to_s,
          content_type: source.content_type.presence || 'image/png'
        )
        # Re-derive the image-style palette from the copied background (async).
        Creatives::DeriveCarouselPaletteJob.perform_later(@owner.id) if @owner.is_a?(Client)
        @owner
      end
    end
  end
end
