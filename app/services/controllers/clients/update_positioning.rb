# frozen_string_literal: true

module Controllers
  module Clients
    # Replaces a client's positioning bag (from the client detail page editor).
    class UpdatePositioning < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        client = workspace.clients.find(@params[:id])
        Operations::Clients::UpdatePositioning.call(client:, positioning: positioning_params)
        { client: serialize(client.reload, ClientSerializer) }
      end

      private

      def positioning_params
        @params.require(:positioning).permit(POSITIONING_PERMIT).to_h
      end
    end
  end
end
