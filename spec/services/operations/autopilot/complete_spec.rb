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

  it 'completes the run at production and requests approval' do
    expect(Operations::Approvals::RequestApproval).to receive(:call).with(hash_including(ticket: ticket))
    Operations::Autopilot::Complete.call(run: run)
    expect(run.reload.state).to eq('completed')
    expect(run.finished_at).to be_present
    expect(ticket.reload.status).to eq('production')
  end
end
