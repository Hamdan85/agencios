# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Approvals::RequestChanges do
  include ActiveJob::TestHelper

  before { ActiveJob::Base.queue_adapter = :test }

  let(:owner) { User.create!(email: "o-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'O') }
  let(:ws) { Operations::Workspaces::SetupForUser.call(user: owner, name: 'Studio') }
  let(:client) { ws.clients.create!(name: 'ACME', email: 'c@acme.co') }
  let(:project) { ws.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) { Ticket.create!(workspace: ws, project: project, status: :production, assignee: owner) }

  before { Current.workspace = ws }
  after { Current.reset }

  def creative(type)
    Creative.create!(workspace: ws, ticket: ticket, creative_type: type, status: :ready, approval_state: 'pending')
  end

  it 'marks the creative changes_requested with feedback and writes history' do
    c = creative('carousel')
    AutopilotRun.create!(workspace: ws, ticket: ticket, user: owner, scope: 'ticket', state: 'completed', progress: {})
    allow(Operations::Autopilot::Regenerate).to receive(:call)

    described_class.call(creative: c, feedback: 'Mais contraste', actor: client)

    expect(c.reload.approval_state).to eq('changes_requested')
    expect(c.client_feedback).to eq('Mais contraste')
    expect(ticket.notes.where(kind: 'system').last.display_body).to include('ajustes')
  end

  it 'starts a regeneration for a non-video creative under GO' do
    c = creative('carousel')
    run = AutopilotRun.create!(workspace: ws, ticket: ticket, user: owner, scope: 'ticket', state: 'completed', progress: {})
    expect(Operations::Autopilot::Regenerate).to receive(:call)
      .with(hash_including(creative: c, feedback: 'Mais contraste'))

    described_class.call(creative: c, feedback: 'Mais contraste', actor: client)
  end

  it 'never regenerates a video creative — it stays in production' do
    c = creative('ugc_video')
    AutopilotRun.create!(workspace: ws, ticket: ticket, user: owner, scope: 'ticket', state: 'completed', progress: {})
    expect(Operations::Autopilot::Regenerate).not_to receive(:call)

    described_class.call(creative: c, feedback: 'Refazer', actor: client)
    expect(ticket.reload.status).to eq('production')
  end

  it 'does not regenerate a manual (non-GO) ticket — stays in production' do
    c = creative('carousel') # no autopilot run
    expect(Operations::Autopilot::Regenerate).not_to receive(:call)

    described_class.call(creative: c, feedback: 'Refazer', actor: client)
    expect(ticket.reload.status).to eq('production')
  end
end
