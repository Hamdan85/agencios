# frozen_string_literal: true

module Controllers
  module McpConnector
    # The current user's Claude connector URL (tokenized MCP endpoint). The token
    # is generated on first read so the URL is always ready to copy.
    class Show < Base
      def call
        token = user.mcp_connector_token!
        { url: connector_url(token), token: token }
      end

      private

      def connector_url(token)
        "#{SystemConfig.app_host}/mcp/c/#{token}"
      end
    end
  end
end
