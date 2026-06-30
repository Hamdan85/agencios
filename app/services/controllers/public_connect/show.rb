# frozen_string_literal: true

module Controllers
  module PublicConnect
    # Data for the public connect page: the client, the agency's brand (name +
    # primary color), and each network's current connection state so the page can
    # show "Conectado ✓" without exposing any tokens.
    class Show < Base
      def initialize(token:)
        @token = token
      end

      def call
        client = client_from_token(@token)
        workspace = client.workspace
        connected = client.social_accounts.status_connected.map(&:provider)

        {
          token: @token,
          client_name: client.name,
          agency_name: workspace.name,
          brand_color: workspace.brand_primary_color,
          networks: NETWORKS.map { |n| { key: n, connected: connected.include?(n) } }
        }
      end
    end
  end
end
