# frozen_string_literal: true

module Controllers
  module Clients
    # POST /clients/:id/carousel_background — sets the client's carousel background
    # image by copying it from an existing platform creative. (Uploads go through
    # the brand_assets action.) Manager-gated, like the rest of client management.
    class SetCarouselBackground < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        client = workspace.clients.find(@params[:id])
        creative = workspace.creatives.find(@params[:creative_id])
        Operations::BrandAssets::AttachFromCreative.call(owner: client, creative: creative)
        { client: serialize(client.reload, ClientSerializer) }
      end
    end
  end
end
