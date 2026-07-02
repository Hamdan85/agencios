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
