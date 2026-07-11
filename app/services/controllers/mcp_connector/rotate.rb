# frozen_string_literal: true

module Controllers
  module McpConnector
    # Rotates the connector token, invalidating the old URL. Used when a URL may
    # have leaked.
    class Rotate < Base
      def call
        unless user.mcp_available?
          raise Operations::Errors::Forbidden,
                I18n.t('api.mcp.plan_required')
        end

        user.rotate_mcp_connector_token!
        Controllers::McpConnector::Show.call
      end
    end
  end
end
