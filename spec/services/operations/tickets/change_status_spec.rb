# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Operations::Tickets::ChangeStatus' do
  before do
    @user, @workspace = Operations::Users::Register.call(
      email: 'cs@agencios.app', password: 'secret123', name: 'CS', workspace_name: 'CS Agency'
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
    allow(SummarizeTicketJob).to receive(:perform_later)
    allow(CarryOverFieldsJob).to receive(:perform_later)
  end

  after { Current.reset }

  describe 'entering "published" (No ar)' do
    it 'auto-closes every still-open subtask on the ticket' do
      open_one = Operations::Subtasks::Create.call(ticket: @ticket, title: 'Editar vídeo')
      open_two = Operations::Subtasks::Create.call(ticket: @ticket, title: 'Escrever legenda')
      already_done = Operations::Subtasks::Create.call(ticket: @ticket, title: 'Aprovar roteiro')
      Operations::Subtasks::Update.call(already_done, done: true)

      Operations::Tickets::ChangeStatus.call(@ticket, 'published', user: @user, force: true)

      expect(@ticket.reload.status).to eq('published')
      expect(@ticket.subtasks.open).to be_empty
      expect(open_one.reload.done).to be(true)
      expect(open_two.reload.done).to be(true)
      expect(already_done.reload.done).to be(true)
    end
  end

  describe 'other transitions' do
    it 'does not touch subtasks when not entering published' do
      subtask = Operations::Subtasks::Create.call(ticket: @ticket, title: 'Rascunhar ideia')

      Operations::Tickets::ChangeStatus.call(@ticket, 'scoping', user: @user)

      expect(subtask.reload.done).to be(false)
    end
  end
end
