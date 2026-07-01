# frozen_string_literal: true

require 'rails_helper'

# OAuth 2.1 / MCP discovery documents Claude reads before any token exists.
RSpec.describe 'MCP OAuth discovery', type: :request do
  it 'advertises the protected resource (RFC 9728) pointing at /mcp' do
    get '/.well-known/oauth-protected-resource'
    expect(response).to have_http_status(:ok)

    body = JSON.parse(response.body)
    expect(body['resource']).to end_with('/mcp')
    expect(body['authorization_servers']).to be_present
    expect(body['scopes_supported']).to include('read', 'write')
  end

  it 'advertises the authorization server (RFC 8414) with S256 PKCE + DCR' do
    get '/.well-known/oauth-authorization-server'
    expect(response).to have_http_status(:ok)

    body = JSON.parse(response.body)
    expect(body['authorization_endpoint']).to end_with('/oauth/authorize')
    expect(body['token_endpoint']).to end_with('/oauth/token')
    expect(body['registration_endpoint']).to end_with('/oauth/register')
    expect(body['code_challenge_methods_supported']).to eq(['S256'])
    expect(body['grant_types_supported']).to include('authorization_code', 'refresh_token')
  end
end
