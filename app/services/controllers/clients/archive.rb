# frozen_string_literal: true

module Controllers
  module Clients
    class Archive < Base
      def initialize(params:)
        @params = params
      end

      def call
        client = workspace.clients.find(@params[:id])
        authorize!(client, :archive?)
        Operations::Clients::Archive.call(client)
        { client: serialize(client, ClientSerializer) }
      end
    end
  end
end
