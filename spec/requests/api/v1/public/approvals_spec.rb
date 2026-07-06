# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public approvals', type: :request do
  let(:ws) { Workspace.create!(name: 'Agência', slug: "ws-#{SecureRandom.hex(4)}") }
  let(:client) { Client.create!(workspace: ws, name: 'Cliente', email: 'c@c.co') }
  let(:project) { Project.create!(workspace: ws, client: client, name: 'P', status: :active, settings: { 'auto_publish_after_approval' => false }) }
  let(:ticket) { Ticket.create!(workspace: ws, project: project, status: :production, channels: ['instagram']) }
  let!(:creative) { Creative.create!(workspace: ws, ticket: ticket, creative_type: 'carousel', status: :ready) }
  let(:token) { ticket.approval_token! }

  it 'loads the approval bundle without auth' do
    get "/api/v1/public/approvals/#{token}"
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['branding']['name']).to eq('Agência')
    expect(body['creatives'].first['id']).to eq(creative.id)
  end

  it 'records a per-creative approval' do
    post "/api/v1/public/approvals/#{token}/creatives/#{creative.id}/approve", as: :json
    expect(response).to have_http_status(:ok)
    expect(creative.reload.approval_approved?).to be(true)
    expect(creative.reviewed_by).to eq(client)
  end

  it '404s on a bad token' do
    get '/api/v1/public/approvals/nope'
    expect(response).to have_http_status(:not_found)
  end
end
