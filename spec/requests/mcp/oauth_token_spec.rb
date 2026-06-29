# frozen_string_literal: true

require "rails_helper"

# The PKCE (S256) authorization-code → token exchange at the token endpoint.
# We seed the access grant directly (the interactive consent page is exercised
# end-to-end via MCP Inspector / Claude) to focus on PKCE enforcement.
RSpec.describe "MCP OAuth token exchange (PKCE)", type: :request do
  let(:user) do
    Operations::Users::Register.call(
      email: "pkce@agencios.app", password: "secret123", name: "PKCE", workspace_name: "PKCE Co"
    ).first.tap { Current.reset }
  end

  let(:application) do
    Doorkeeper::Application.create!(
      name: "Claude", redirect_uri: "https://claude.ai/callback",
      scopes: "read write", confidential: false
    )
  end

  let(:verifier) { SecureRandom.urlsafe_base64(64).tr("=", "")[0, 64] }
  let(:challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(verifier)).tr("=", "") }

  def grant_with_challenge
    Doorkeeper::AccessGrant.create!(
      application: application, resource_owner_id: user.id,
      redirect_uri: application.redirect_uri, expires_in: 600, scopes: "read write",
      code_challenge: challenge, code_challenge_method: "S256"
    )
  end

  it "exchanges the code for an access + refresh token with the correct verifier" do
    grant = grant_with_challenge
    post "/oauth/token", params: {
      grant_type: "authorization_code", code: grant.token,
      redirect_uri: application.redirect_uri, client_id: application.uid,
      code_verifier: verifier
    }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["access_token"]).to be_present
    expect(body["refresh_token"]).to be_present
    expect(Doorkeeper::AccessToken.by_token(body["access_token"]).resource_owner_id).to eq(user.id)
  end

  it "rejects the exchange when the PKCE verifier is wrong" do
    grant = grant_with_challenge
    post "/oauth/token", params: {
      grant_type: "authorization_code", code: grant.token,
      redirect_uri: application.redirect_uri, client_id: application.uid,
      code_verifier: "wrong-verifier"
    }

    expect(response).to have_http_status(:bad_request)
  end
end
