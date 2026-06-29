# frozen_string_literal: true

require "rails_helper"

# RFC 7591 Dynamic Client Registration — how Claude registers itself.
RSpec.describe "MCP dynamic client registration", type: :request do
  it "registers a public client (no secret) and flags it as dynamic" do
    post "/oauth/register", params: {
      client_name: "Claude",
      redirect_uris: ["https://claude.ai/api/mcp/auth_callback"],
      token_endpoint_auth_method: "none",
      grant_types: ["authorization_code", "refresh_token"],
      scope: "read write"
    }, as: :json

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body["client_id"]).to be_present
    expect(body).not_to have_key("client_secret")
    expect(body["token_endpoint_auth_method"]).to eq("none")

    app = Doorkeeper::Application.find_by(uid: body["client_id"])
    expect(app.dynamically_registered).to be(true)
    expect(app.confidential).to be(false)
  end

  it "returns a secret for a confidential client" do
    post "/oauth/register", params: {
      client_name: "Server App",
      redirect_uris: ["https://example.com/callback"],
      token_endpoint_auth_method: "client_secret_basic"
    }, as: :json

    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body)["client_secret"]).to be_present
  end

  it "rejects a non-https redirect_uri" do
    post "/oauth/register", params: {
      client_name: "Bad", redirect_uris: ["http://evil.example.com/cb"]
    }, as: :json

    expect(response).to have_http_status(:bad_request)
    expect(JSON.parse(response.body)["error"]).to eq("invalid_client_metadata")
  end

  it "rejects a registration with no redirect_uris" do
    post "/oauth/register", params: { client_name: "Bad" }, as: :json
    expect(response).to have_http_status(:bad_request)
  end
end
