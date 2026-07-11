# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Approvals::ApproveSlot do
  include ActiveJob::TestHelper

  before { ActiveJob::Base.queue_adapter = :test }

  let(:owner) { User.create!(email: "o-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'O') }
  let(:ws) { Operations::Workspaces::SetupForUser.call(user: owner, name: 'Studio') }
  let(:client) { ws.clients.create!(name: 'ACME') }
  let(:project) { ws.projects.create!(client: client, name: 'Camp', color: '#7C3AED', settings: { 'auto_publish_after_approval' => false }) }
  let(:ticket) do
    Ticket.create!(workspace: ws, project: project, status: :production, assignee: owner, scheduled_at: 2.days.from_now,
                   fields: { 'scoping' => { 'creative_types' => %w[carousel feed_image] } })
  end

  before { Current.workspace = ws }
  after { Current.reset }

  def creative(type)
    Creative.create!(workspace: ws, ticket: ticket, creative_type: type, status: :ready, approval_state: 'pending')
  end

  it 'approves the chosen option and marks siblings not_selected' do
    a = creative('carousel')
    b = creative('carousel')
    described_class.call(ticket: ticket, creative_type: 'carousel', chosen_creative_id: a.id, actor: client)
    expect(a.reload.approval_state).to eq('approved')
    expect(b.reload.approval_state).to eq('not_selected')
  end

  it 'auto-picks the sole option of a single-option slot' do
    img = creative('feed_image')
    described_class.call(ticket: ticket, creative_type: 'feed_image', chosen_creative_id: nil, actor: client)
    expect(img.reload.approval_state).to eq('approved')
  end

  it 'raises when a multi-option slot has no chosen option' do
    creative('carousel')
    creative('carousel')
    expect { described_class.call(ticket: ticket, creative_type: 'carousel', chosen_creative_id: nil, actor: client) }
      .to raise_error(Operations::Errors::Invalid)
  end

  it 'defers advancing only once the LAST slot is approved (undo window)' do
    car = creative('carousel')
    img = creative('feed_image')

    # First slot: no advance scheduled yet (feed_image still pending).
    expect { described_class.call(ticket: ticket, creative_type: 'carousel', chosen_creative_id: car.id, actor: client) }
      .not_to have_enqueued_job(OnFullyApprovedJob)
    expect(ticket.reload.status).to eq('production')

    # Last slot completes the ticket → deferred advance enqueued.
    expect { described_class.call(ticket: ticket, creative_type: 'feed_image', chosen_creative_id: img.id, actor: client) }
      .to have_enqueued_job(OnFullyApprovedJob).with(ticket.id)

    perform_enqueued_jobs
    expect(ticket.reload.status).to eq('scheduled')
  end

  it 'writes a granular history note per slot' do
    car = creative('carousel')
    described_class.call(ticket: ticket, creative_type: 'carousel', chosen_creative_id: car.id, actor: client)
    expect(ticket.notes.where(kind: 'system').last.display_body).to include('Carrossel')
  end

  it 'undo reverts approved + not_selected back to pending within the window' do
    a = creative('carousel')
    b = creative('carousel')
    described_class.call(ticket: ticket, creative_type: 'carousel', chosen_creative_id: a.id, actor: client)
    Operations::Approvals::Undo.call(ticket: ticket.reload, actor: client)
    expect(a.reload.approval_state).to eq('pending')
    expect(b.reload.approval_state).to eq('pending')
  end
end
