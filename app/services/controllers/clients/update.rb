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
        client.update!(attributes)
        Operations::Clients::UpdatePositioning.call(client:, positioning:) unless positioning.nil?
        { client: serialize(client.reload, ClientSerializer) }
      end

      private

      def client_params
        @params.require(:client).permit(*ATTRS_PERMIT, positioning: POSITIONING_PERMIT)
      end
    end
  end
end
