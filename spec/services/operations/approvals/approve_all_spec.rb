# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Approvals::ApproveAll do
  let(:ws) { Workspace.create!(name: 'WS', slug: "ws-#{SecureRandom.hex(4)}") }
  let(:client) { Client.create!(workspace: ws, name: 'C', email: 'c@c.co') }
  let(:project) { Project.create!(workspace: ws, client: client, name: 'P', status: :active, settings: { 'auto_publish_after_approval' => false }) }
  let(:ticket) { Ticket.create!(workspace: ws, project: project, status: :approval, channels: ['instagram']) }
  let(:user) { User.create!(email: 'm@a.co', password: 'password123', name: 'Manager') }
  let!(:c1) { Creative.create!(workspace: ws, ticket: ticket, creative_type: 'carousel', status: :ready) }
  let!(:c2) { Creative.create!(workspace: ws, ticket: ticket, creative_type: 'image', status: :ready) }

  before { Current.workspace = ws }

  it 'approves every approvable creative with the internal actor' do
    described_class.call(ticket: ticket, actor: user)
    expect([c1, c2].map { |c| c.reload.approval_state }).to eq(%w[approved approved])
    expect(ticket.reload.fully_approved?).to be(true)
    expect(ticket.approval_actor).to eq(user)
  end

  it 'picks the newest option per multi-option slot, marking the rest not_selected' do
    older = c1
    newer = Creative.create!(workspace: ws, ticket: ticket, creative_type: 'carousel', status: :ready)
    described_class.call(ticket: ticket, actor: user)
    expect(newer.reload.approval_state).to eq('approved')
    expect(older.reload.approval_state).to eq('not_selected')
    expect(ticket.reload.fully_approved?).to be(true)
  end
end
