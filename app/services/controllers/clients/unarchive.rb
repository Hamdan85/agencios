# frozen_string_literal: true

module Controllers
  module Clients
    # Reactivating a client re-occupies a plan slot, so it re-checks the
    # active-client limit — archiving to free a slot is fine, but the freed
    # slot can't be double-used.
    class Unarchive < Base
      def initialize(params:)
        @params = params
      end

      def call
        client = workspace.clients.find(@params[:id])
        authorize!(client, :archive?)
        raise Operations::Errors::ClientLimitReached unless workspace.within_client_limit?

        Operations::Clients::Unarchive.call(client)
        { client: serialize(client, ClientSerializer) }
      end
    end
  end
end
