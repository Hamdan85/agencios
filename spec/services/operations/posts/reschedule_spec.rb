# frozen_string_literal: true

require 'rails_helper'

# Publishing is sweep-based (MonitorScheduledPostsJob reads Post#scheduled_at),
# so a ticket-level schedule edit MUST land on the still-scheduled posts or the
# old time still publishes.
RSpec.describe Operations::Posts::Reschedule do
  let(:user) { User.create!(email: 'resched@agencios.app', password: 'secret123', name: 'Res') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) do
    Operations::Tickets::Create.call(
      workspace: workspace, user: user,
      params: { project_id: project.id, title: 'T', channels: %w[instagram], scheduled_at: 1.day.from_now }
    ).tap { |t| Operations::Tickets::ChangeStatus.call(t, 'scheduled', user: user, force: true) }
  end

  before do
    allow(Broadcaster).to receive(:ticket)
    allow(Broadcaster).to receive(:board)
    ActiveJob::Base.queue_adapter = :test
    Current.workspace = workspace
  end

  after { Current.reset }

  def build_post(status:, at: 1.day.from_now)
    account = client.social_accounts.find_by(provider: 'instagram') ||
              client.social_accounts.create!(workspace: workspace, provider: 'instagram')
    Post.create!(workspace: workspace, ticket: ticket, social_account: account,
                 status: status, scheduled_at: at)
  end

  it 'moves still-scheduled posts and leaves published ones untouched' do
    new_time = 3.days.from_now.change(hour: 10)
    scheduled = build_post(status: :scheduled)
    published = build_post(status: :published, at: 2.days.ago)

    described_class.call(ticket: ticket, scheduled_at: new_time)

    expect(scheduled.reload.scheduled_at).to be_within(1.second).of(new_time)
    expect(published.reload.scheduled_at).to be_within(1.second).of(2.days.ago)
  end

  it 'is a no-op on a blank time' do
    post = build_post(status: :scheduled)
    expect { described_class.call(ticket: ticket, scheduled_at: nil) }
      .not_to(change { post.reload.scheduled_at })
  end

  it 'propagates through the posting-step field save (UpdateFields)' do
    post = build_post(status: :scheduled)
    new_time = 4.days.from_now.change(hour: 9)

    Operations::Tickets::UpdateFields.call(
      ticket: ticket, status: 'scheduled', values: { 'scheduled_at' => new_time.iso8601 }
    )

    expect(post.reload.scheduled_at).to be_within(1.second).of(new_time)
    expect(ticket.reload.scheduled_at).to be_within(1.second).of(new_time)
  end

  it 'propagates through a plain ticket update (drawer meta / calendar drag)' do
    post = build_post(status: :scheduled)
    new_time = 5.days.from_now.change(hour: 14)

    Operations::Tickets::Update.call(ticket: ticket, params: { scheduled_at: new_time })

    expect(post.reload.scheduled_at).to be_within(1.second).of(new_time)
  end
end
