# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public client central (portal)', type: :request do
  let(:owner) { User.create!(email: "o-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'O') }
  let(:ws) { Operations::Workspaces::SetupForUser.call(user: owner, name: 'Studio') }
  let(:client) { ws.clients.create!(name: 'ACME', email: 'c@acme.co') }
  let(:token) { client.approval_token! }

  def json = JSON.parse(response.body)

  it 'lists the client campaigns except drafts, with status-driven tabs' do
    active = ws.projects.create!(client: client, name: 'Ativa', color: '#7C3AED', status: :active)
    done = ws.projects.create!(client: client, name: 'Fim', color: '#059669', status: :completed)
    done.reports.create!(workspace: ws, status: :ready, data: { 'kpis' => {} })
    ws.projects.create!(client: client, name: 'Rascunho', color: '#000', status: :draft)

    get "/api/v1/public/portal/#{token}"
    expect(response).to have_http_status(:ok)
    expect(json['agency']['name']).to eq('Studio')
    names = json['campaigns'].map { |c| c['name'] }
    expect(names).to contain_exactly('Ativa', 'Fim')

    active_c = json['campaigns'].find { |c| c['name'] == 'Ativa' }
    done_c = json['campaigns'].find { |c| c['name'] == 'Fim' }
    expect(active_c['available_tabs']).to include('quadro', 'metricas')
    expect(done_c['available_tabs']).to eq(%w[quadro relatorio])
    expect(done_c['has_report']).to be(true)
  end

  it 'returns a read-only board scoped to the campaign' do
    project = ws.projects.create!(client: client, name: 'Ativa', color: '#7C3AED', status: :active)
    Ticket.create!(workspace: ws, project: project, status: :production, channels: ['instagram'])

    get "/api/v1/public/portal/#{token}/campaigns/#{project.id}/board"
    expect(response).to have_http_status(:ok)
    statuses = json['columns'].map { |c| c['status'] }
    expect(statuses).to eq(Ticket::WORKFLOW.map(&:to_s))
    prod = json['columns'].find { |c| c['status'] == 'production' }
    expect(prod['tickets'].size).to eq(1)
    expect(prod['tickets'].first).to have_key('subtasks_done')
  end

  it 'returns campaign metrics via the overview aggregator' do
    project = ws.projects.create!(client: client, name: 'Ativa', color: '#7C3AED', status: :active)
    get "/api/v1/public/portal/#{token}/campaigns/#{project.id}/metrics"
    expect(response).to have_http_status(:ok)
    expect(json['overview']).to have_key('kpis')
  end

  it 'returns the finalized report data' do
    project = ws.projects.create!(client: client, name: 'Fim', color: '#059669', status: :completed)
    project.reports.create!(workspace: ws, status: :ready, data: { 'kpis' => { 'views' => 10 } }, overall_score: 8.0)

    get "/api/v1/public/portal/#{token}/campaigns/#{project.id}/report"
    expect(response).to have_http_status(:ok)
    expect(json['status']).to eq('ready')
    expect(json.dig('report', 'data', 'kpis', 'views')).to eq(10)
  end

  it 'cannot see another client\'s campaign' do
    other = ws.clients.create!(name: 'Other')
    other_project = ws.projects.create!(client: other, name: 'Alheia', color: '#000', status: :active)
    get "/api/v1/public/portal/#{token}/campaigns/#{other_project.id}/board"
    expect(response).to have_http_status(:not_found)
  end

  it '404s an invalid token' do
    get '/api/v1/public/portal/nope-nope'
    expect(response).to have_http_status(:not_found)
  end
end
