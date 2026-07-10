# frozen_string_literal: true

module Controllers
  module Clients
    class Update < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        client = workspace.clients.find(@params[:id])
        attributes = client_params
        positioning = attributes.delete(:positioning)
        was_image = client.carousel_image?
        client.update!(attributes)
        Operations::Clients::UpdatePositioning.call(client:, positioning:) unless positioning.nil?
        derive_palette_if_needed(client, was_image)
        { client: serialize(client.reload, ClientSerializer) }
      end

      private

      # When the style flips TO `image` and a background is already attached but
      # no palette has been derived yet, kick off the analysis (async). Switching
      # away leaves the stored palette untouched (harmless — only read in image mode).
      def derive_palette_if_needed(client, was_image)
        return if was_image || !client.carousel_image?
        return unless client.carousel_background.attached?
        return if client.carousel_image_palette['source_signature'].present?

        Creatives::DeriveCarouselPaletteJob.perform_later(client.id)
      end

      def client_params
        @params.require(:client).permit(*ATTRS_PERMIT, positioning: POSITIONING_PERMIT)
      end
    end
  end
end
