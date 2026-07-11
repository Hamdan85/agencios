# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Approvals::NotifyDecision do
  include ActiveJob::TestHelper

  before { ActiveJob::Base.queue_adapter = :test }

  let(:user) { User.create!(email: "resp-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'Resp') }
  let(:ws) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio') }
  let(:client) { ws.clients.create!(name: 'ACME') }
  let(:project) { ws.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) { Ticket.create!(workspace: ws, project: project, status: :production, assignee: user) }

  before { Current.workspace = ws }
  after { Current.reset }

  it 'writes an approval history note and emails the responsible user' do
    expect do
      perform_enqueued_jobs do
        described_class.call(ticket: ticket, decision: 'approved', actor: client)
      end
    end.to change { ticket.notes.where(kind: 'system').count }.by(1)

    expect(ticket.notes.order(:created_at).last.display_body).to include('aprovou')
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([user.email])
  end

  it 'writes a changes-requested note carrying the feedback' do
    creative = Creative.create!(workspace: ws, ticket: ticket, creative_type: 'carousel', status: :ready)
    perform_enqueued_jobs do
      described_class.call(ticket: ticket, decision: 'changes_requested', actor: client,
                           creative: creative, feedback: 'Trocar a cor de fundo')
    end
    expect(ticket.notes.order(:created_at).last.display_body).to include('ajustes').and include('Trocar a cor')
  end

  describe 'Ticket#responsible_user' do
    it 'prefers the assignee, then falls back to the workspace owner' do
      expect(ticket.responsible_user).to eq(user)
      ticket.update!(assignee: nil)
      expect(ticket.responsible_user).to eq(ws.owner)
    end
  end
end
