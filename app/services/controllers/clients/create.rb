# frozen_string_literal: true

module Controllers
  module Clients
    class Create < Base
      def initialize(params:)
        @params = params
      end

      def call
        authorize!(Client, :create?)
        raise Operations::Errors::ClientLimitReached unless workspace.within_client_limit?

        client = Operations::Clients::Create.call(client_params)
        { client: serialize(client, ClientSerializer) }
      end

      private

      def client_params
        @params.require(:client).permit(*ATTRS_PERMIT, positioning: POSITIONING_PERMIT)
      end
    end
  end
end
