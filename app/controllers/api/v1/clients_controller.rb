# frozen_string_literal: true

module Api
  module V1
    class ClientsController < BaseController
      def index   = render_ok(Controllers::Clients::Index.call(params:))
      def show    = render_ok(Controllers::Clients::Show.call(params:))
      def create  = render_created(Controllers::Clients::Create.call(params:))
      def update  = render_ok(Controllers::Clients::Update.call(params:))
      def destroy = render_ok(Controllers::Clients::Destroy.call(params:))

      # POST /api/v1/clients/:id/archive
      def archive = render_ok(Controllers::Clients::Archive.call(params:))

      # POST /api/v1/clients/positioning_preview — AI-synthesized positioning
      # (stateless; used by the creation wizard before the client exists).
      def positioning_preview = render_ok(Controllers::Clients::PositioningPreview.call(params:))

      # POST /api/v1/clients/extract_from_url — fetches a brand's landing page and
      # returns a full client draft (contact + brand + positioning) for the wizard
      # to pre-fill (stateless; used before the client exists).
      def extract_from_url = render_ok(Controllers::Clients::ExtractFromUrl.call(params:))

      # PATCH /api/v1/clients/:id/positioning — replace a client's positioning.
      def update_positioning = render_ok(Controllers::Clients::UpdatePositioning.call(params:))

      # PATCH /api/v1/clients/:id/brand_assets — upload the client's logo and/or
      # creator avatar (multipart). Brand text fields go through #update.
      def brand_assets = render_ok(Controllers::Clients::UpdateBrandAssets.call(params:))
    end
  end
end
