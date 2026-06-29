# frozen_string_literal: true

module Oauth
  # OAuth 2.1 / MCP discovery documents. Public, unauthenticated. These let
  # Claude find our authorization server and register itself before any token
  # exists.
  class MetadataController < ActionController::API
    SCOPES = %w[read write billing].freeze

    # GET /.well-known/oauth-protected-resource  (RFC 9728)
    # The MCP server (/mcp) is the protected resource; it points at this host as
    # its authorization server.
    def protected_resource
      render json: {
        resource: "#{base_url}/mcp",
        authorization_servers: [base_url],
        scopes_supported: SCOPES,
        bearer_methods_supported: %w[header]
      }
    end

    # GET /.well-known/oauth-authorization-server  (RFC 8414)
    def authorization_server
      render json: {
        issuer: base_url,
        authorization_endpoint: "#{base_url}/oauth/authorize",
        token_endpoint: "#{base_url}/oauth/token",
        registration_endpoint: "#{base_url}/oauth/register",
        introspection_endpoint: "#{base_url}/oauth/introspect",
        revocation_endpoint: "#{base_url}/oauth/revoke",
        scopes_supported: SCOPES,
        response_types_supported: %w[code],
        grant_types_supported: %w[authorization_code refresh_token],
        token_endpoint_auth_methods_supported: %w[none client_secret_basic client_secret_post],
        code_challenge_methods_supported: %w[S256],
        authorization_response_iss_parameter_supported: true
      }
    end

    private

    def base_url
      request.base_url
    end
  end
end
