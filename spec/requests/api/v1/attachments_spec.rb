# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Attachments", type: :request do
  before do
    ActiveJob::Base.queue_adapter = :test
    @user, @workspace = Operations::Users::Register.call(
      email: "files@agencios.app", password: "secret123", name: "Files", workspace_name: "Files Agency"
    )
    Current.reset
    client = @workspace.clients.create!(name: "ACME")
    @project = @workspace.projects.create!(client: client, name: "Camp", color: "#7C3AED")
    @ticket = Operations::Tickets::Create.call(
      workspace: @workspace, user: @user,
      params: { project_id: @project.id, title: "Reel", creative_type: "reel", channels: %w[instagram] }
    )
  end

  def login
    post "/api/v1/session", params: { email: "files@agencios.app", password: "secret123" }, as: :json
    expect(response).to have_http_status(:ok)
  end

  def txt = fixture_file_upload("sample.txt", "text/plain")
  def png = fixture_file_upload("sample.png", "image/png")

  it "uploads a file and exposes it across statuses" do
    login
    expect do
      post "/api/v1/tickets/#{@ticket.id}/attachments", params: { file: txt, title: "Brief" }
    end.to change { @ticket.attachments.count }.by(1)

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    att = body["attachments"].first
    expect(att["kind"]).to eq("document")
    expect(att["display_name"]).to eq("Brief")
    expect(att["url"]).to be_present

    # The ticket payload carries attachments regardless of workflow status.
    @ticket.update!(status: :published)
    get "/api/v1/tickets/#{@ticket.id}"
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["attachments"].size).to eq(1)
  end

  it "derives image kind and a preview thumbnail" do
    login
    post "/api/v1/tickets/#{@ticket.id}/attachments", params: { file: png }
    att = JSON.parse(response.body)["attachments"].first
    expect(att["kind"]).to eq("image")
    expect(att["preview_url"]).to be_present
  end

  it "uploads multiple files in one request (one row per file)" do
    login
    expect do
      post "/api/v1/tickets/#{@ticket.id}/attachments", params: { files: [txt, png] }
    end.to change { @ticket.attachments.count }.by(2)
    expect(JSON.parse(response.body)["attachments"].size).to eq(2)
  end

  it "renames a file" do
    login
    att = Operations::Attachments::Create.call(ticket: @ticket, file: txt, uploaded_by: @user)
    patch "/api/v1/tickets/#{@ticket.id}/attachments/#{att.id}",
          params: { attachment: { title: "Roteiro final" } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(att.reload.title).to eq("Roteiro final")
  end

  it "lets the uploader remove their own file" do
    login
    att = Operations::Attachments::Create.call(ticket: @ticket, file: txt, uploaded_by: @user)
    expect do
      delete "/api/v1/tickets/#{@ticket.id}/attachments/#{att.id}"
    end.to change { @ticket.attachments.count }.by(-1)
    expect(response).to have_http_status(:ok)
  end

  it "rejects an empty upload" do
    login
    post "/api/v1/tickets/#{@ticket.id}/attachments", params: {}
    expect(response).to have_http_status(:unprocessable_content).or have_http_status(:unprocessable_entity)
  end

  it "blocks unauthenticated access" do
    post "/api/v1/tickets/#{@ticket.id}/attachments", params: { file: txt }
    expect(response).to have_http_status(:unauthorized)
  end
end
