# frozen_string_literal: true

require 'rails_helper'

# The calendar merges scheduled posts, planned funnel tickets, meetings and dated
# subtasks. A GO-mode ticket sits in `production` with a `scheduled_at` (its
# planned publish moment) but NO post yet — it must still surface, otherwise the
# whole month reads as empty. Once the ticket produces a post, the post takes
# over and the ticket drops off (no double entry).
RSpec.describe Controllers::Calendar::Index do
  let(:user) { User.create!(email: 'cal@agencios.app', password: 'secret123', name: 'Cal') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }

  let(:when_at) { Time.zone.parse('2026-07-13 07:00') }

  def ticket_with_schedule
    t = Operations::Tickets::Create.call(
      workspace: workspace, user: user,
      params: { project_id: project.id, title: 'Planned', channels: %w[instagram] }
    )
    t.update!(status: :production, scheduled_at: when_at)
    t
  end

  before do
    allow(Broadcaster).to receive(:ticket)
    allow(Broadcaster).to receive(:board)
    Current.workspace = workspace
    Current.membership = workspace.memberships.find_by(user: user)
    Current.actor = user
  end

  after { Current.reset }

  def call
    described_class.call(
      params: ActionController::Parameters.new(from: '2026-07-01', to: '2026-07-31')
    )[:events]
  end

  it 'surfaces a planned funnel ticket that has a scheduled_at but no post' do
    ticket = ticket_with_schedule

    events = call
    ticket_events = events.select { |e| e[:type] == 'ticket' }

    expect(ticket_events.size).to eq(1)
    expect(ticket_events.first).to include(
      id: "ticket-#{ticket.id}", ticket_id: ticket.id,
      title: ticket.display_title, color: project.color, client_name: 'ACME'
    )
  end

  it 'drops the ticket once it has a post (the post_event takes over — no double entry)' do
    ticket = ticket_with_schedule
    account = client.social_accounts.create!(workspace: workspace, provider: 'instagram')
    Post.create!(workspace: workspace, ticket: ticket, social_account: account,
                 status: :scheduled, scheduled_at: when_at)

    events = call

    expect(events.select { |e| e[:type] == 'ticket' }).to be_empty
    expect(events.select { |e| e[:type] == 'post' }.size).to eq(1)
  end

  it 'omits tickets of archived projects (calendar is live planning)' do
    ticket_with_schedule
    project.update!(status: :archived)

    expect(call.select { |e| e[:type] == 'ticket' }).to be_empty
  end
end
