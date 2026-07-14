# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Autopilot::Complete do
  let(:ws) { Workspace.create!(name: 'WS', slug: "ws-#{SecureRandom.hex(4)}") }
  let(:client) { Client.create!(workspace: ws, name: 'C', email: 'c@c.co') }
  let(:project) { Project.create!(workspace: ws, client: client, name: 'P', status: :active, settings: { 'require_client_approval' => true }) }
  let(:ticket) { Ticket.create!(workspace: ws, project: project, status: :production) }
  let(:user) { User.create!(email: 'u@a.co', password: 'password123', name: 'U') }
  let(:run) { AutopilotRun.create!(workspace: ws, ticket: ticket, user: user, scope: 'ticket', state: 'generating', progress: { 'generation_ids' => [], 'creative_ids' => [] }) }

  before do
    Current.workspace = ws
    allow(Operations::Push::Notify).to receive(:call)
  end

  # GO stops with the work done, NOT sent: a human reviews it in Produção and
  # clicks "Enviar para aprovação" (which is what asks the client).
  it 'completes the run and leaves the ticket in production for the team to send' do
    Creative.create!(workspace: ws, ticket: ticket, creative_type: 'carousel', status: :ready)
    expect(Operations::Approvals::RequestApproval).not_to receive(:call)

    Operations::Autopilot::Complete.call(run: run)

    expect(run.reload.state).to eq('completed')
    expect(run.finished_at).to be_present
    expect(ticket.reload.status).to eq('production')
    expect(ticket.approval_requested_at).to be_nil
  end
end
