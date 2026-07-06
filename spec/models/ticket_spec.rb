# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ticket do
  let(:ws) { Workspace.create!(name: 'WS', slug: "ws-#{SecureRandom.hex(4)}") }
  let(:client) { Client.create!(workspace: ws, name: 'Cliente', email: 'c@cli.co') }
  let(:project) { Project.create!(workspace: ws, client: client, name: 'Camp', status: :active) }
  let(:ticket) { Ticket.create!(workspace: ws, project: project, status: :production) }

  it 'mints a stable approval token' do
    token = ticket.approval_token!
    expect(token).to be_present
    expect(ticket.approval_token!).to eq(token) # idempotent
  end

  it 'excludes superseded creatives and reports full approval' do
    old = Creative.create!(workspace: ws, ticket: ticket, creative_type: 'carousel', status: :ready)
    fresh = Creative.create!(workspace: ws, ticket: ticket, creative_type: 'carousel', status: :ready, parent: old)
    expect(ticket.approvable_creatives).to contain_exactly(fresh)

    expect(ticket.fully_approved?).to be(false)
    fresh.update!(approval_state: 'approved', reviewed_by: client, decided_at: Time.current)
    expect(ticket.reload.fully_approved?).to be(true)
    expect(ticket.approval_actor).to eq(client)
  end
end
