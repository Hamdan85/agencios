# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Client approval queue', type: :model do
  let(:ws) { Workspace.create!(name: 'WS', slug: "ws-#{SecureRandom.hex(4)}") }
  let(:client) { Client.create!(workspace: ws, name: 'C') }
  let(:project) { Project.create!(workspace: ws, client: client, name: 'P', status: :active) }

  def ticket_with_creative(status:, approval_state:, requested: true)
    t = Ticket.create!(workspace: ws, project: project, status: :approval,
                       approval_requested_at: requested ? Time.current : nil)
    Creative.create!(workspace: ws, ticket: t, creative_type: 'carousel', status: status, approval_state: approval_state)
    t
  end

  describe 'Client#approval_token!' do
    it 'mints once and stays stable' do
      first = client.approval_token!
      expect(first).to start_with('apv_')
      expect(client.approval_token!).to eq(first)
    end
  end

  describe 'Ticket.awaiting_client_approval / Client#pending_approval_tickets' do
    it 'includes a requested ticket with a pending ready creative' do
      t = ticket_with_creative(status: :ready, approval_state: 'pending')
      expect(client.pending_approval_tickets).to include(t)
    end

    it 'excludes tickets that are approved, changes_requested, or never requested' do
      approved = ticket_with_creative(status: :ready, approval_state: 'approved')
      changed  = ticket_with_creative(status: :ready, approval_state: 'changes_requested')
      not_req  = ticket_with_creative(status: :ready, approval_state: 'pending', requested: false)

      queue = client.pending_approval_tickets
      expect(queue).not_to include(approved, changed, not_req)
    end
  end
end
