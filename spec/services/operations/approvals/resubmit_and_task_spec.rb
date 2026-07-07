# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Client rejection → task + resubmit' do
  include ActiveJob::TestHelper

  before { ActiveJob::Base.queue_adapter = :test }

  let(:owner) { User.create!(email: "o-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'O') }
  let(:ws) { Operations::Workspaces::SetupForUser.call(user: owner, name: 'Studio') }
  let(:client) { ws.clients.create!(name: 'ACME', email: 'c@acme.co') }
  let(:project) { ws.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) { Ticket.create!(workspace: ws, project: project, status: :production, assignee: owner, approval_requested_at: Time.current) }
  let!(:creative) { Creative.create!(workspace: ws, ticket: ticket, creative_type: 'carousel', status: :ready, approval_state: 'pending') }

  before { Current.workspace = ws }
  after { Current.reset }

  describe 'bug #1 — a review task is created for the ticket owner on changes' do
    it 'creates a subtask assigned to the responsible user' do
      expect do
        Operations::Approvals::RequestChanges.call(creative: creative, feedback: 'Trocar as cores', actor: client)
      end.to change { ticket.subtasks.count }.by(1)
      task = ticket.subtasks.order(:created_at).last
      expect(task.assignee_id).to eq(owner.id)
      expect(task.title).to include('ajustes')
    end
  end

  describe 'bug #2 — resubmitting reopens the rejected pieces as pending' do
    it 'resets changes_requested creatives back to pending so they reappear in the queue' do
      Operations::Approvals::RequestChanges.call(creative: creative, feedback: 'Refazer', actor: client)
      expect(creative.reload.approval_state).to eq('changes_requested')
      expect(client.pending_approval_tickets).to be_empty # left the queue after rejection

      Operations::Approvals::RequestApproval.call(ticket: ticket, sent_by: owner)

      expect(creative.reload.approval_state).to eq('pending')
      expect(client.pending_approval_tickets.map(&:id)).to include(ticket.id) # reopened
    end

    it 'RequestApproval mints the client token so the portal link resolves' do
      Operations::Approvals::RequestApproval.call(ticket: ticket, sent_by: owner)
      expect(client.reload.approval_token).to be_present
    end
  end
end
