# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Client approve + undo' do
  include ActiveJob::TestHelper

  before { ActiveJob::Base.queue_adapter = :test }

  let(:user) { User.create!(email: "u-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'U') }
  let(:ws) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio') }
  let(:client) { ws.clients.create!(name: 'ACME') }
  let(:project) { ws.projects.create!(client: client, name: 'Camp', color: '#7C3AED', settings: { 'auto_publish_after_approval' => false }) }
  let(:ticket) { Ticket.create!(workspace: ws, project: project, status: :production, assignee: user, scheduled_at: 2.days.from_now) }

  before do
    Current.workspace = ws
    Creative.create!(workspace: ws, ticket: ticket, creative_type: 'carousel', status: :ready, approval_state: 'pending')
  end

  after { Current.reset }

  it 'approves immediately but defers advancing (undo window)' do
    expect do
      Operations::Approvals::ApproveTicket.call(ticket: ticket, actor: client)
    end.to have_enqueued_job(OnFullyApprovedJob).with(ticket.id)

    expect(ticket.reload.fully_approved?).to be(true)
    expect(ticket.status).to eq('production') # NOT advanced yet
  end

  it 'advances when the deferred job runs (no undo)' do
    Operations::Approvals::ApproveTicket.call(ticket: ticket, actor: client)
    perform_enqueued_jobs
    expect(ticket.reload.status).to eq('scheduled')
  end

  it 'undo before the job reverts to pending; the deferred job then no-ops' do
    Operations::Approvals::ApproveTicket.call(ticket: ticket, actor: client) # job enqueued, not run
    Operations::Approvals::Undo.call(ticket: ticket.reload, actor: client)   # reverts to pending
    perform_enqueued_jobs                                                    # deferred job runs → no-op
    expect(ticket.reload.status).to eq('production')
    expect(ticket.approvable_creatives.all?(&:approval_pending?)).to be(true)
  end

  it 'refuses undo once the ticket has advanced' do
    Operations::Approvals::ApproveTicket.call(ticket: ticket, actor: client)
    perform_enqueued_jobs
    expect { Operations::Approvals::Undo.call(ticket: ticket.reload, actor: client) }
      .to raise_error(Operations::Errors::Invalid)
  end
end
