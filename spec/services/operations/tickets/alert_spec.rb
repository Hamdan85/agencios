# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Ticket alert state' do
  before do
    @user, @workspace = Operations::Users::Register.call(
      email: 'al@agencios.app', password: 'secret123', name: 'AL', workspace_name: 'AL Agency'
    )
    Current.workspace = @workspace
    Current.membership = @workspace.memberships.find_by(user: @user)
    client = @workspace.clients.create!(name: 'ACME')
    project = @workspace.projects.create!(client: client, name: 'P', color: '#7C3AED')
    @ticket = Operations::Tickets::Create.call(
      workspace: @workspace, user: @user, params: { project_id: project.id, title: 'T' }
    )
    allow(Broadcaster).to receive(:ticket)
    allow(Broadcaster).to receive(:board)
    allow(Operations::Push::Notify).to receive(:call)
  end

  after { Current.reset }

  describe 'Operations::Tickets::RaiseAlert' do
    it 'flags the ticket and generates a task carrying the failure context' do
      expect do
        Operations::Tickets::RaiseAlert.call(
          ticket: @ticket,
          reason: 'Falha ao publicar em instagram: token expirado',
          task_title: 'Resolver publicação em instagram'
        )
      end.to change { @ticket.subtasks.count }.by(1)

      expect(@ticket.reload.in_alert?).to be(true)
      expect(@ticket.alert_reason).to include('token expirado')
      task = @ticket.subtasks.order(:created_at).last
      expect(task.title).to eq('Resolver publicação em instagram')
      expect(task.assignee_id).to eq(@user.id) # falls back to creator
    end

    it 'does not stack a duplicate open task for the same failure' do
      2.times do
        Operations::Tickets::RaiseAlert.call(
          ticket: @ticket, reason: 'x', task_title: 'Resolver publicação em instagram'
        )
      end
      expect(@ticket.subtasks.where(title: 'Resolver publicação em instagram').count).to eq(1)
    end
  end

  describe 'Operations::Tickets::ClearAlert' do
    it 'clears the alert (and is a no-op when not in alert)' do
      Operations::Tickets::ClearAlert.call(ticket: @ticket) # no-op, no raise
      Operations::Tickets::RaiseAlert.call(ticket: @ticket, reason: 'boom')
      expect(@ticket.reload.in_alert?).to be(true)

      Operations::Tickets::ClearAlert.call(ticket: @ticket)
      expect(@ticket.reload.in_alert?).to be(false)
    end
  end
end
