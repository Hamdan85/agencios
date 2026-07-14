# frozen_string_literal: true

require 'rails_helper'

# The Aprovação stage's own rules: entering it IS asking for approval, it can't be
# entered empty, approving leaves it for Postagem, and a rejection bounces the
# ticket back to Produção.
RSpec.describe 'Approval stage' do
  include ActiveJob::TestHelper

  let(:owner) { User.create!(email: "o-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'O') }
  let(:ws) { Operations::Workspaces::SetupForUser.call(user: owner, name: 'Studio') }
  let(:client) { ws.clients.create!(name: 'ACME', email: 'c@acme.co') }
  let(:project) { ws.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) do
    Ticket.create!(workspace: ws, project: project, status: :production,
                   assignee: owner, channels: ['instagram'], creative_types: ['carousel'])
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    ActionMailer::Base.deliveries.clear
    Current.workspace = ws
  end
  after { Current.reset }

  def ready_creative
    Creative.create!(workspace: ws, ticket: ticket, creative_type: 'carousel',
                     status: :ready, approval_state: 'pending')
  end

  def advance_to_approval = Operations::Tickets::ChangeStatus.call(ticket, 'approval', user: owner)

  it 'sits between production and scheduled in the funnel' do
    expect(Ticket::WORKFLOW).to eq(%i[ideation scoping production approval scheduled published retrospective done])
  end

  it 'refuses to enter approval with nothing to approve' do
    expect { advance_to_approval }.to raise_error(Operations::Errors::InvalidTransition)
    expect(ticket.reload.status).to eq('production')
  end

  it 'treats entering approval as the request: the client gets the link' do
    ready_creative
    perform_enqueued_jobs { advance_to_approval }

    expect(ticket.reload.status).to eq('approval')
    expect(ticket.approval_requested_at).to be_present
    expect(ActionMailer::Base.deliveries.last.to).to eq(['c@acme.co'])
    expect(client.pending_approval_tickets.map(&:id)).to include(ticket.id)
  end

  it 'stops in approval without emailing when the campaign approves internally' do
    project.update!(settings: { 'require_client_approval' => false })
    ready_creative
    ActionMailer::Base.deliveries.clear
    perform_enqueued_jobs { advance_to_approval }

    expect(ticket.reload.status).to eq('approval')
    expect(ActionMailer::Base.deliveries).to be_empty
    # Never asked → stays out of the client's portal, waiting on the team instead.
    expect(ticket.approval_requested_at).to be_nil
    expect(client.pending_approval_tickets).to be_empty
  end

  it 'leaves approval for postagem once every slot is approved' do
    ready_creative
    advance_to_approval

    Operations::Approvals::ApproveAll.call(ticket: ticket.reload, actor: owner)

    expect(ticket.reload.status).to eq('scheduled')
    expect(ticket.fully_approved?).to be(true)
  end

  it 'refuses an internal approval outside the approval stage' do
    ready_creative
    expect { Operations::Approvals::ApproveAll.call(ticket: ticket, actor: owner) }
      .to raise_error(Operations::Errors::Invalid)
  end

  it 'bounces back to production when the client rejects a piece' do
    creative = ready_creative
    advance_to_approval

    Operations::Approvals::RequestChanges.call(creative: creative, feedback: 'Mais contraste', actor: client)

    expect(ticket.reload.status).to eq('production')
    expect(creative.reload.approval_state).to eq('changes_requested')
    expect(client.pending_approval_tickets).to be_empty
  end

  it 'reopens the rejected piece when it is resubmitted' do
    creative = ready_creative
    advance_to_approval
    Operations::Approvals::RequestChanges.call(creative: creative, feedback: 'Mais contraste', actor: client)

    advance_to_approval # the resubmission is the move back into Aprovação

    expect(ticket.reload.status).to eq('approval')
    expect(creative.reload.approval_state).to eq('pending')
    expect(creative.client_feedback).to be_nil
  end
end
