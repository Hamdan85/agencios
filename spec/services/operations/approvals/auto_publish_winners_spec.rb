# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Approvals::AutoPublishApproved do
  let(:ws) { Workspace.create!(name: 'WS', slug: "ws-#{SecureRandom.hex(4)}") }
  let(:client) { Client.create!(workspace: ws, name: 'C') }
  let(:project) { Project.create!(workspace: ws, client: client, name: 'P', status: :active) }
  let(:ticket) { Ticket.create!(workspace: ws, project: project, status: :scheduled, scheduled_at: 1.day.from_now) }

  before { Current.workspace = ws }
  after { Current.reset }

  it 'publishes only the chosen winner, never the not_selected loser' do
    winner = Creative.create!(workspace: ws, ticket: ticket, creative_type: 'carousel', status: :ready, approval_state: 'approved')
    Creative.create!(workspace: ws, ticket: ticket, creative_type: 'carousel', status: :ready, approval_state: 'not_selected')

    expect(Operations::Tickets::Publish).to receive(:call).with(hash_including(creative_ids: [winner.id.to_s]))
    described_class.call(ticket: ticket)
  end
end
