# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Approvals::DecideCreative do
  let(:ws) { Workspace.create!(name: 'WS', slug: "ws-#{SecureRandom.hex(4)}") }
  let(:client) { Client.create!(workspace: ws, name: 'C', email: 'c@c.co') }
  let(:project) do
    Project.create!(workspace: ws, client: client, name: 'P', status: :active,
                    settings: { 'auto_publish_after_approval' => true,
                                'posting_window' => { 'weekdays' => [0, 1, 2, 3, 4, 5, 6], 'times' => ['09:00'], 'min_gap_minutes' => 0, 'timezone' => 'America/Sao_Paulo' } })
  end
  let(:ticket) { Ticket.create!(workspace: ws, project: project, status: :production, channels: ['instagram']) }
  let!(:creative) { Creative.create!(workspace: ws, ticket: ticket, creative_type: 'carousel', status: :ready) }

  before { Current.workspace = ws }

  it 'marks changes_requested without advancing' do
    described_class.call(creative: creative, decision: 'changes_requested', actor: client, feedback: 'trocar cor')
    expect(creative.reload.approval_changes_requested?).to be(true)
    expect(creative.client_feedback).to eq('trocar cor')
    expect(ticket.reload.status).to eq('production')
  end

  it 'approves and, when fully approved + auto-publish ON, advances to Publication AND creates posts' do
    allow(Operations::Tickets::Publish).to receive(:call).and_return({ posts: [1], skipped: [] })
    described_class.call(creative: creative, decision: 'approved', actor: client)

    expect(creative.reload.approval_approved?).to be(true)
    expect(creative.reviewed_by).to eq(client)
    expect(ticket.reload.status).to eq('scheduled')          # entered the Publication phase
    expect(ticket.scheduled_at).to be_present                # reasonable slot pre-filled
    expect(Operations::Tickets::Publish).to have_received(:call).with(hash_including(mode: 'scheduled'))
  end

  it 'with auto-publish OFF, advances to Publication phase but does NOT create posts' do
    project.update!(settings: project.settings.merge('auto_publish_after_approval' => false))
    allow(Operations::Tickets::Publish).to receive(:call)
    described_class.call(creative: creative, decision: 'approved', actor: client)

    expect(ticket.reload.status).to eq('scheduled')          # phase still entered
    expect(ticket.scheduled_at).to be_present                # default schedule pre-filled
    expect(Operations::Tickets::Publish).not_to have_received(:call) # team confirms in the phase
  end
end
