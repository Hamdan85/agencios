# frozen_string_literal: true

require "rails_helper"

# The total paywall: no free tier. An authenticated user whose active workspace
# is not billing-active is blocked (402) on every endpoint except the allowlist
# (billing, credits, me, workspace, auth).
RSpec.describe "Api::V1 total paywall", type: :request do
  before do
    @user, @workspace = Operations::Users::Register.call(
      email: "owner@agencios.app", password: "secret123", name: "Owner", workspace_name: "Studio"
    )
    Current.reset
  end

  after { Current.reset }

  def login = post("/api/v1/session", params: { email: "owner@agencios.app", password: "secret123" }, as: :json)

  it "blocks a normal endpoint with 402 for a freshly-registered (unpaid) workspace" do
    login
    get "/api/v1/board"
    expect(response).to have_http_status(:payment_required)
    expect(JSON.parse(response.body)["code"]).to eq("billing_required")
  end

  it "still allows /me behind the paywall" do
    login
    get "/api/v1/me"
    expect(response).to have_http_status(:ok)
  end

  it "still allows the billing screen behind the paywall" do
    login
    get "/api/v1/billing"
    expect(response).to have_http_status(:ok)
  end

  it "lets a billing-active workspace through" do
    activate_billing(@workspace)
    login
    get "/api/v1/board"
    expect(response).to have_http_status(:ok)
  end

  it "lets a godfathered workspace through without any subscription" do
    @workspace.update!(godfathered: true)
    login
    get "/api/v1/board"
    expect(response).to have_http_status(:ok)
  end
end
