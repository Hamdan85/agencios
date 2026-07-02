# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Strategy::Apply do
  let(:user) { User.create!(email: 'strat@agencios.app', password: 'secret123', name: 'Strat') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:session) { StrategySession.create!(workspace: workspace, project: project, user: user, status: 'active') }

  before do
    allow(Broadcaster).to receive(:board)
    allow(Broadcaster).to receive(:ticket)
    allow(::Strategy::FillTicketJob).to receive(:perform_later)
    Current.workspace = workspace
  end

  after { Current.reset }

  # Seed the session with a previously-applied batch of real tickets.
  def seed_applied_batch(*titles)
    titles.map do |t|
      Operations::Tickets::Create.call(
        workspace: workspace, user: user,
        params: { project_id: project.id, title: t, strategy_session_id: session.id }
      )
    end
  end

  it 'ADDITIVE plan appends the new ticket and keeps the existing batch' do
    existing = seed_applied_batch('Existing A', 'Existing B')
    session.update!(status: 'proposed', proposed_plan: {
      'mode' => 'append',
      'tickets' => [{ 'key' => 't1', 'title' => 'Tartaruga lenta', 'creative_type' => 'feed_image',
                      'channels' => ['instagram'], 'scheduled_at' => 1.week.from_now.iso8601, 'additive' => true }]
    })

    created = described_class.call(session: session, user: user)

    expect(created.map(&:title)).to eq(['Tartaruga lenta'])
    expect(existing.all? { |t| Ticket.exists?(t.id) }).to be(true)
    expect(session.reload.tickets.pluck(:title)).to contain_exactly('Existing A', 'Existing B', 'Tartaruga lenta')
    expect(session.status).to eq('applied')
  end

  it 'OPS plan removes a ticket and keeps the rest, without discarding' do
    a, b = seed_applied_batch('Keep', 'Remove me')
    session.update!(status: 'proposed', proposed_plan: {
      'mode' => 'append',
      'tickets' => [{ 'key' => "r#{b.id}", 'op' => 'remove', 'ticket_id' => b.id, 'title' => 'Remove me' }]
    })

    created = described_class.call(session: session, user: user)

    expect(created).to be_empty
    expect(Ticket.exists?(a.id)).to be(true)
    expect(Ticket.exists?(b.id)).to be(false)
    expect(session.reload.status).to eq('applied')
  end

  it 'OPS plan edits an existing ticket in place (no new ticket, no discard)' do
    a, = seed_applied_batch('Old title')
    session.update!(status: 'proposed', proposed_plan: {
      'mode' => 'append',
      'tickets' => [{ 'key' => "r#{a.id}", 'op' => 'update', 'ticket_id' => a.id,
                      'title' => 'New title', 'creative_type' => 'carousel', 'channels' => ['instagram'],
                      'priority' => 'high', 'scheduled_at' => 3.days.from_now.iso8601 }]
    })

    expect { described_class.call(session: session, user: user) }
      .not_to change { workspace.tickets.count }
    a.reload
    expect(a.title).to eq('New title')
    expect(a.creative_type).to eq('carousel')
    expect(a.priority).to eq('high')
  end

  it 'OPS plan mixes create + update + remove in one apply' do
    keep, gone = seed_applied_batch('Keep & edit', 'Delete')
    session.update!(status: 'proposed', proposed_plan: {
      'mode' => 'append',
      'tickets' => [
        { 'key' => 't1', 'op' => 'create', 'title' => 'Brand new', 'creative_type' => 'feed_image',
          'channels' => ['instagram'], 'scheduled_at' => 2.days.from_now.iso8601, 'additive' => true },
        { 'key' => "r#{keep.id}", 'op' => 'update', 'ticket_id' => keep.id, 'title' => 'Edited' },
        { 'key' => "r#{gone.id}", 'op' => 'remove', 'ticket_id' => gone.id, 'title' => 'Delete' }
      ]
    })

    created = described_class.call(session: session, user: user)

    expect(created.map(&:title)).to eq(['Brand new'])
    expect(keep.reload.title).to eq('Edited')
    expect(Ticket.exists?(gone.id)).to be(false)
  end

  it 'FULL (non-additive) plan discards the previous batch and rewrites it' do
    seed_applied_batch('Old 1', 'Old 2')
    session.update!(status: 'proposed', proposed_plan: {
      'tickets' => [{ 'key' => 't1', 'title' => 'New only', 'creative_type' => 'reel',
                      'channels' => ['instagram'], 'scheduled_at' => 1.week.from_now.iso8601 }]
    })

    described_class.call(session: session, user: user)

    expect(session.reload.tickets.pluck(:title)).to eq(['New only'])
  end
end
