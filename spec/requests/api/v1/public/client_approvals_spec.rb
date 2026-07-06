# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public client approval portal', type: :request do
  include ActiveJob::TestHelper

  before { ActiveJob::Base.queue_adapter = :test }

  let(:owner) { User.create!(email: "o-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'O') }
  let(:ws) { Operations::Workspaces::SetupForUser.call(user: owner, name: 'Studio') }
  let(:client) { ws.clients.create!(name: 'ACME') }
  let(:project) { ws.projects.create!(client: client, name: 'Camp', color: '#7C3AED', settings: { 'auto_publish_after_approval' => false }) }

  def pending_ticket
    t = Ticket.create!(workspace: ws, project: project, status: :production, approval_requested_at: Time.current)
    Creative.create!(workspace: ws, ticket: t, creative_type: 'carousel', status: :ready, approval_state: 'pending')
    t
  end

  it 'lists only the tickets awaiting this client’s approval' do
    pending = pending_ticket
    approved = Ticket.create!(workspace: ws, project: project, status: :production, approval_requested_at: Time.current)
    Creative.create!(workspace: ws, ticket: approved, creative_type: 'carousel', status: :ready, approval_state: 'approved')

    get "/api/v1/public/client_approvals/#{client.approval_token!}"
    body = JSON.parse(response.body)

    expect(response).to have_http_status(:ok)
    expect(body['agency']['name']).to eq('Studio')
    ids = body['tickets'].map { |t| t['id'] }
    expect(ids).to eq([pending.id])
  end

  it 'approves a ticket and drops it from the returned queue' do
    ticket = pending_ticket
    post "/api/v1/public/client_approvals/#{client.approval_token!}/tickets/#{ticket.id}/approve"
    body = JSON.parse(response.body)

    expect(response).to have_http_status(:ok)
    expect(body['tickets'].map { |t| t['id'] }).not_to include(ticket.id) # approved → left the queue
    expect(ticket.reload.fully_approved?).to be(true)
  end

  it 'records a change request on a creative' do
    ticket = pending_ticket
    creative = ticket.creatives.first
    post "/api/v1/public/client_approvals/#{client.approval_token!}/tickets/#{ticket.id}/request_changes",
         params: { creative_id: creative.id, feedback: 'Mais contraste' }, as: :json

    expect(response).to have_http_status(:ok)
    expect(creative.reload.approval_state).to eq('changes_requested')
    expect(creative.client_feedback).to eq('Mais contraste')
  end

  it '404s on a bad token' do
    get '/api/v1/public/client_approvals/nope'
    expect(response).to have_http_status(:not_found)
  end
end
