# frozen_string_literal: true

require "rails_helper"

RSpec.describe "End-to-end smoke", type: :request do
  before do
    ActiveJob::Base.queue_adapter = :test
    @user, @workspace = Operations::Users::Register.call(
      email: "smoke@agencios.app", password: "secret123", name: "Smoke", workspace_name: "Smoke Agency"
    )
    Current.reset
    activate_billing(@workspace)
    @client = nil
    @workspace.clients.create!(name: "ACME").tap do |c|
      @project = @workspace.projects.create!(client: c, name: "Camp", color: "#7C3AED")
    end
    @ticket = Operations::Tickets::Create.call(
      workspace: @workspace, user: @user,
      params: { project_id: @project.id, title: "Reel teste", creative_type: "reel", channels: %w[instagram] }
    )
  end

  def login
    post "/api/v1/session", params: { email: "smoke@agencios.app", password: "secret123" }, as: :json
    expect(response).to have_http_status(:ok)
  end

  it "routes every HTML path to the SPA shell" do
    # Root is the SSR marketing landing page; the catch-all serves the React
    # shell for the in-app Portuguese frontend routes.
    expect(Rails.application.routes.recognize_path("/")).to include(controller: "pages", action: "home")
    %w[/painel /quadro /tickets/1 /clientes].each do |path|
      expect(Rails.application.routes.recognize_path(path)).to include(controller: "spa", action: "index")
    end
    shell = Rails.root.join("app/views/spa/index.html.erb").read
    expect(shell).to include('id="root"')
    expect(shell).to include("csrf-token")
    expect(shell).to include('vite_javascript_tag "application.jsx"')
  end

  it "logs in and returns the workspace" do
    login
    body = JSON.parse(response.body)
    expect(body.dig("workspace", "name")).to eq("Smoke Agency")
    expect(body.dig("workspace", "role")).to eq("owner")
  end

  it "serves the board grouped by status" do
    login
    get "/api/v1/board"
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["columns"].map { |c| c["status"] }).to eq(Ticket::WORKFLOW.map(&:to_s))
    ideation = body["columns"].find { |c| c["status"] == "ideation" }
    expect(ideation["tickets"].first["display_title"]).to eq("Reel teste")
  end

  it "serves the dashboard, calendar, clients, studio, billing" do
    login
    %w[dashboard calendar clients studio billing settings tasks meetings invoices generations].each do |path|
      get "/api/v1/#{path}"
      expect(response).to have_http_status(:ok), "expected 200 for /api/v1/#{path}, got #{response.status}: #{response.body[0, 120]}"
    end
  end

  it "advances a ticket through the funnel via ChangeStatus" do
    login
    post "/api/v1/tickets/#{@ticket.id}/advance", params: { to_status: "scoping" }, as: :json
    expect(response).to have_http_status(:ok)
    expect(@ticket.reload.status).to eq("scoping")
    expect(@ticket.ticket_status_logs.count).to eq(1)
  end

  it "blocks unauthenticated API access" do
    get "/api/v1/board"
    expect(response).to have_http_status(:unauthorized)
  end
end
