# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Approvals::RequestChanges do
  include ActiveJob::TestHelper

  before { ActiveJob::Base.queue_adapter = :test }

  let(:owner) { User.create!(email: "o-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'O') }
  let(:ws) { Operations::Workspaces::SetupForUser.call(user: owner, name: 'Studio') }
  let(:client) { ws.clients.create!(name: 'ACME', email: 'c@acme.co') }
  let(:project) { ws.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) { Ticket.create!(workspace: ws, project: project, status: :approval, assignee: owner) }

  before { Current.workspace = ws }
  after { Current.reset }

  def creative(type)
    Creative.create!(workspace: ws, ticket: ticket, creative_type: type, status: :ready, approval_state: 'pending')
  end

  it 'marks the creative changes_requested with feedback and writes history' do
    c = creative('carousel')

    described_class.call(creative: c, feedback: 'Mais contraste', actor: client)

    expect(c.reload.approval_state).to eq('changes_requested')
    expect(c.client_feedback).to eq('Mais contraste')
    # The rejection note, then the bounce back to Produção — both land in history.
    bodies = ticket.notes.where(kind: 'system').map(&:display_body)
    expect(bodies).to include(a_string_including('ajustes'))
    expect(bodies.last).to eq('Status: Aprovação → Produção')
    expect(ticket.reload.status).to eq('production')
  end

  # A client's "pedir ajustes" must never spend the workspace's credits — not even
  # on a GO ticket. The piece is redone by the TEAM, from Produção.
  it 'never regenerates anything under GO — no credits are spent on a rejection' do
    c = creative('carousel')
    AutopilotRun.create!(workspace: ws, ticket: ticket, user: owner, scope: 'ticket', state: 'completed', progress: {})
    expect(Operations::Creatives::GenerateViralCarousel).not_to receive(:call)
    expect(Operations::Creatives::GenerateImage).not_to receive(:call)

    expect { described_class.call(creative: c, feedback: 'Mais contraste', actor: client) }
      .not_to change { ws.credit_transactions.count }
    expect(ticket.reload.status).to eq('production')
  end

  it 'leaves a manual (non-GO) ticket in production with the feedback' do
    c = creative('carousel')

    described_class.call(creative: c, feedback: 'Refazer', actor: client)

    expect(ticket.reload.status).to eq('production')
    expect(c.reload.client_feedback).to eq('Refazer')
  end
end
