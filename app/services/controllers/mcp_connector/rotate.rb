# frozen_string_literal: true

module Controllers
  module McpConnector
    # Rotates the connector token, invalidating the old URL. Used when a URL may
    # have leaked.
    class Rotate < Base
      def call
        unless workspace&.mcp_enabled?
          raise Operations::Errors::Forbidden,
                'O conector do Claude requer o plano Agência ou Enterprise.'
        end

        user.rotate_mcp_connector_token!
        Controllers::McpConnector::Show.call
      end
    end
  end
end
