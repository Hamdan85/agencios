# frozen_string_literal: true

module Controllers
  module Clients
    # Attaches the client's brand assets (logo and/or creator avatar) from a
    # multipart upload. Manager-gated, like the rest of client management.
    class UpdateBrandAssets < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        client = workspace.clients.find(@params[:id])
        Operations::Clients::UpdateBrandAssets.call(
          client: client, logo: @params[:logo], default_creator_avatar: @params[:default_creator_avatar]
        )
        { client: serialize(client.reload, ClientSerializer) }
      end
    end
  end
end
