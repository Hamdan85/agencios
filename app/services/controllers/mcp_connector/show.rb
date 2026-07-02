# frozen_string_literal: true

module Controllers
  module McpConnector
    # The current user's Claude connector URL (tokenized MCP endpoint). The token
    # is personal (one per user, all their workspaces), so availability is gated
    # at the user level: it unlocks once ANY of the user's workspaces is on an
    # Agência+ plan with an active subscription. The token is generated on first
    # read so the URL is always ready to copy.
    class Show < Base
      def call
        return locked_payload unless user.mcp_available?

        token = user.mcp_connector_token!
        { enabled: true, url: connector_url(token), token: token }
      end

      private

      def locked_payload
        {
          enabled: false, upgrade_required: true, min_plan: 'agencia',
          upgrade_url: "#{SystemConfig.app_host}/assinatura"
        }
      end

      def connector_url(token)
        "#{SystemConfig.app_host}/mcp/c/#{token}"
      end
    end
  end
end
