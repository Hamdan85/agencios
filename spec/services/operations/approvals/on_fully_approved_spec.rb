# frozen_string_literal: true

require 'rails_helper'

# Approval always advances the ticket into the Publication phase. Whether the
# scheduled posts are also created hands-off depends on the ticket: the project
# may opt in (auto_publish_after_approval), and a GO ticket always does — the
# client's "yes" is what the paused autopilot was waiting for.
RSpec.describe Operations::Approvals::OnFullyApproved do
  let(:ws) { Workspace.create!(name: 'WS', slug: "ws-#{SecureRandom.hex(4)}") }
  let(:user) { User.create!(email: "u-#{SecureRandom.hex(3)}@a.co", password: 'password123', name: 'U') }
  let(:client) { Client.create!(workspace: ws, name: 'C') }
  let(:project) do
    Project.create!(workspace: ws, client: client, name: 'P', status: :active,
                    settings: { 'auto_publish_after_approval' => false })
  end
  let(:ticket) { Ticket.create!(workspace: ws, project: project, status: :approval) }

  before do
    Current.workspace = ws
    Creative.create!(workspace: ws, ticket: ticket, creative_type: 'carousel',
                     status: :ready, approval_state: 'approved')
  end

  after { Current.reset }

  it 'advances to the publication phase and waits for the team (manual ticket)' do
    expect(Operations::Approvals::AutoPublishApproved).not_to receive(:call)

    described_class.call(ticket: ticket)

    expect(ticket.reload.status).to eq('scheduled')
    expect(ticket.scheduled_at).to be_present
  end

  it 'resumes GO and schedules the posts when the ticket ran on autopilot' do
    AutopilotRun.create!(workspace: ws, ticket: ticket, user: user, scope: 'ticket',
                         state: 'completed', progress: {})
    expect(Operations::Approvals::AutoPublishApproved).to receive(:call).with(hash_including(ticket: ticket))

    described_class.call(ticket: ticket)

    expect(ticket.reload.status).to eq('scheduled')
  end

  it 'does not resume a GO run that failed — the team took over' do
    AutopilotRun.create!(workspace: ws, ticket: ticket, user: user, scope: 'ticket',
                         state: 'failed', progress: {})
    expect(Operations::Approvals::AutoPublishApproved).not_to receive(:call)

    described_class.call(ticket: ticket)
  end
end
