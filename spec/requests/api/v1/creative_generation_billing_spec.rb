# frozen_string_literal: true

require "rails_helper"

# Generation consumes paid resources, so it is gated behind an active
# subscription / trial (SPECIFICATION.md §9 — "generation blocked if
# !access_granted?"). The gate short-circuits before any vendor call.
RSpec.describe "Api::V1 creative generation billing gate", type: :request do
  include ActiveJob::TestHelper

  before do
    ActiveJob::Base.queue_adapter = :test
    @user, @workspace = Operations::Users::Register.call(
      email: "owner@agencios.app", password: "secret123", name: "Owner", workspace_name: "Studio"
    )
    Current.reset
    client = @workspace.clients.create!(name: "ACME")
    project = @workspace.projects.create!(client: client, name: "Camp", color: "#7C3AED")
    @ticket = Operations::Tickets::Create.call(
      workspace: @workspace, user: @user,
      params: { project_id: project.id, title: "Img", creative_type: "image", channels: %w[instagram] }
    )
  end

  after { Current.reset }

  def login(email = "owner@agencios.app")
    post "/api/v1/session", params: { email: email, password: "secret123" }, as: :json
    expect(response).to have_http_status(:ok)
  end

  def generate(kind: "image")
    post "/api/v1/tickets/#{@ticket.id}/creatives/generate", params: { kind: kind }, as: :json
  end

  it "blocks generation with 402 when billing is inactive (trial lapsed)" do
    @workspace.subscription.update!(status: "canceled", trial_ends_at: 1.day.ago)
    login

    generate

    expect(response).to have_http_status(:payment_required)
    expect(JSON.parse(response.body)["code"]).to eq("billing_required")
  end

  it "blocks guests with 403 before reaching the credit gate" do
    activate_billing(@workspace) # past the total paywall so the guest gate is reached
    guest = User.create!(email: "guest@agencios.app", password: "secret123", name: "Guest")
    @workspace.memberships.create!(user: guest, role: :guest)
    login("guest@agencios.app")

    generate

    expect(response).to have_http_status(:forbidden)
  end

  it "blocks image generation with 402 insufficient_credits when the wallet is empty" do
    activate_billing(@workspace) # billing is fine, but there are no credits
    login

    generate(kind: "image")

    expect(response).to have_http_status(:payment_required)
    expect(JSON.parse(response.body)["code"]).to eq("insufficient_credits")
  end
end
