# frozen_string_literal: true

module Mcp
  # Tokenized MCP connector endpoint at /mcp/c/:token.
  #
  # This is the way agencios is added to Claude as a custom connector: the user
  # copies their personal connector URL (which embeds a secret token) from
  # Settings and pastes it into Claude. The token in the path IS the credential —
  # no OAuth handshake — so Claude connects directly. Everything else (CORS,
  # origin guard, JSON-RPC dispatch, tools) is inherited from ServerController.
  class ConnectorController < ServerController
    private

    # Resolve the actor from the path token. A connector grants the user's full
    # read+write surface; per-tool authorization still happens via Pundit + the
    # membership resolved for each workspace argument (see Mcp::ToolContext).
    def authenticate_token!
      token = params[:token].to_s
      @actor = token.present? && User.find_by(mcp_connector_token: token)
      return connector_unauthorized unless @actor

      @granted_scopes = %w[read write]
      @application_id = nil
    end

    # Unlike the OAuth endpoint, a bad connector token must NOT emit an OAuth
    # WWW-Authenticate challenge (that would make Claude try to start OAuth). Just
    # fail closed with a JSON-RPC error.
    def connector_unauthorized
      render json: rpc_error(nil, -32_001, 'Invalid connector token. Copy a fresh URL from agencios → Configurações → Conector do Claude.'),
             status: :unauthorized
    end
  end
end
