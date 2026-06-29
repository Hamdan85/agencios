# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Notes", type: :request do
  include ActiveJob::TestHelper

  before do
    ActiveJob::Base.queue_adapter = :test
    @user, @workspace = Operations::Users::Register.call(
      email: "owner@agencios.app", password: "secret123", name: "Owner", workspace_name: "Talk Agency"
    )
    Current.reset
    @member = User.create!(email: "mate@agencios.app", password: "secret123", name: "Mate Member")
    @workspace.memberships.create!(user: @member, role: :member)
    @outsider = User.create!(email: "out@agencios.app", password: "secret123", name: "Outsider")

    client = @workspace.clients.create!(name: "ACME")
    @project = @workspace.projects.create!(client: client, name: "Camp", color: "#7C3AED")
    @ticket = Operations::Tickets::Create.call(
      workspace: @workspace, user: @user,
      params: { project_id: @project.id, title: "Reel", creative_type: "reel", channels: %w[instagram] }
    )
  end

  def login(email = "owner@agencios.app")
    post "/api/v1/session", params: { email: email, password: "secret123" }, as: :json
    expect(response).to have_http_status(:ok)
  end

  def txt = fixture_file_upload("sample.txt", "text/plain")
  def png = fixture_file_upload("sample.png", "image/png")

  it "creates a plain comment" do
    login
    expect do
      post "/api/v1/tickets/#{@ticket.id}/notes", params: { note: { body: "Primeiro comentário" } }
    end.to change { @ticket.notes.kind_comment.count }.by(1)

    expect(response).to have_http_status(:created)
    note = JSON.parse(response.body)["note"]
    expect(note["body"]).to eq("Primeiro comentário")
    expect(note["kind"]).to eq("comment")
  end

  it "resolves @mentions to workspace members and emails them" do
    login
    body = "Veja isso @[Mate Member](#{@member.id}) e @[Outsider](#{@outsider.id})"

    # Block form drains nested jobs (NotifyMentionsJob → the mail delivery job).
    perform_enqueued_jobs do
      post "/api/v1/tickets/#{@ticket.id}/notes", params: { note: { body: body, mentioned_user_ids: [@member.id, @outsider.id] } }
    end

    note = JSON.parse(response.body)["note"]
    # The outsider (not a member of this workspace) is filtered out.
    expect(note["mentioned_user_ids"]).to eq([@member.id])
    expect(note["mentions"]).to eq([{ "id" => @member.id, "name" => "Mate Member" }])

    # The job emails the mentioned member, not the author.
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([@member.email])
    expect(mail.subject).to include("Owner")
  end

  it "attaches files to a comment and surfaces them in the ticket file list" do
    login
    expect do
      post "/api/v1/tickets/#{@ticket.id}/notes", params: { note: { body: "Com arquivos", files: [txt, png] } }
    end.to change { @ticket.attachments.count }.by(2)

    note = JSON.parse(response.body)["note"]
    expect(note["attachments"].size).to eq(2)
    expect(@ticket.attachments.where.not(note_id: nil).count).to eq(2)

    # The same files appear in the ticket payload's file list.
    get "/api/v1/tickets/#{@ticket.id}"
    expect(JSON.parse(response.body)["attachments"].size).to eq(2)
  end

  it "allows a files-only comment but rejects an empty one" do
    login
    post "/api/v1/tickets/#{@ticket.id}/notes", params: { note: { body: "", files: [txt] } }
    expect(response).to have_http_status(:created)

    post "/api/v1/tickets/#{@ticket.id}/notes", params: { note: { body: "" } }
    expect(response).to have_http_status(:unprocessable_content).or have_http_status(:unprocessable_entity)
  end

  it "blocks guests from commenting but lets them read the feed" do
    guest = User.create!(email: "guest@agencios.app", password: "secret123", name: "Guest")
    @workspace.memberships.create!(user: guest, role: :guest)
    login("guest@agencios.app")

    post "/api/v1/tickets/#{@ticket.id}/notes", params: { note: { body: "oi" } }
    expect(response).to have_http_status(:forbidden)

    get "/api/v1/tickets/#{@ticket.id}/notes"
    expect(response).to have_http_status(:ok)
  end
end
