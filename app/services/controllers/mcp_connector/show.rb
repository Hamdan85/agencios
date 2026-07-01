# frozen_string_literal: true

module Controllers
  module McpConnector
    # The current user's Claude connector URL (tokenized MCP endpoint). The token
    # is generated on first read so the URL is always ready to copy.
    class Show < Base
      # The connector is an Agência+ feature. For Solo we return a locked payload
      # so the frontend renders an upgrade hook instead of the URL.
      def call
        return locked_payload unless workspace&.mcp_enabled?

        token = user.mcp_connector_token!
        { enabled: true, url: connector_url(token), token: token }
      end

      private

      def locked_payload
        { enabled: false, upgrade_required: true, min_plan: "agencia" }
      end

      def connector_url(token)
        "#{SystemConfig.app_host}/mcp/c/#{token}"
      end
    end
  end
end
