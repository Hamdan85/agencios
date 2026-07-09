# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Report send-to-client', type: :request do
  before do
    ActiveJob::Base.queue_adapter = :test
    allow(Vendors::Render::Pdf).to receive(:call).and_return('%PDF-1.4 fake')
    @user, @workspace = Operations::Users::Register.call(
      email: 'owner@agencios.app', password: 'secret123', name: 'Owner', workspace_name: 'Agency'
    )
    Current.reset
    activate_billing(@workspace)
    @client = @workspace.clients.create!(name: 'ACME', email: 'client@acme.co')
    @project = @workspace.projects.create!(client: @client, name: 'Launch', color: '#7C3AED')
    @report = @project.reports.create!(workspace: @workspace, status: :ready, data: { 'kpis' => {} })
  end

  def login(email = 'owner@agencios.app', password = 'secret123')
    post '/api/v1/session', params: { email: email, password: password }, as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'e-mails the report to the client and stamps sent_to_client_at (manager)' do
    login
    expect do
      post "/api/v1/reports/#{@report.id}/send"
    end.to have_enqueued_mail(ReportMailer, :deck)
    expect(response).to have_http_status(:ok)
    expect(@report.reload.sent_to_client_at).to be_present
  end

  it '422 when the client has no e-mail' do
    @client.update!(email: nil)
    login
    post "/api/v1/reports/#{@report.id}/send"
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'forbids a plain member' do
    member = User.create!(email: 'member@agencios.app', password: 'secret123', name: 'Member')
    Membership.create!(user: member, workspace: @workspace, role: :member)
    login('member@agencios.app')
    post "/api/v1/reports/#{@report.id}/send"
    expect(response).to have_http_status(:forbidden)
  end

  it 'returns 402 without active billing' do
    @workspace.subscription.update!(status: 'incomplete', card_on_file: false)
    login
    post "/api/v1/reports/#{@report.id}/send"
    expect(response).to have_http_status(:payment_required)
  end
end
