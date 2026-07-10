# frozen_string_literal: true

module Controllers
  module Clients
    # POST /clients/:id/rotate_portal_link — mints a fresh approval token, breaking
    # any portal link already shared with the client (e.g. after a leak).
    class RotatePortalLink < Base
      def initialize(params:)
        @params = params
      end

      def call
        client = workspace.clients.find(@params[:id])
        authorize!(client, :update?)
        client.rotate_approval_token!
        { client: serialize(client, ClientSerializer) }
      end
    end
  end
end
