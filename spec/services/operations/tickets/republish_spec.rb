# frozen_string_literal: true

require 'rails_helper'

# Re-publishing (Operations::Tickets::Publish on a ticket that already has
# posts): pending attempts are canceled through Posts::Cancel, history is
# preserved, and an in-flight post blocks the run (a mid-publish destroy would
# orphan content on the network).
RSpec.describe Operations::Tickets::Publish do
  let(:user) { User.create!(email: 'repub@agencios.app', password: 'secret123', name: 'Rep') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:account) { client.social_accounts.create!(workspace: workspace, provider: 'instagram') }
  let(:ticket) do
    Operations::Tickets::Create.call(
      workspace: workspace, user: user,
      params: { project_id: project.id, title: 'T', channels: %w[instagram], scheduled_at: 1.day.from_now }
    ).tap do |t|
      Operations::Tickets::UpdateFields.call(ticket: t, status: 'scoping', values: { 'creative_types' => %w[feed_image] })
      Operations::Tickets::ChangeStatus.call(t, 'scheduled', user: user, force: true)
    end
  end
  let!(:creative) do
    ticket.creatives.create!(workspace: workspace, creative_type: 'feed_image', source: :uploaded, status: :ready)
                    .tap { |c| c.assets.attach(io: StringIO.new('img'), filename: 'a.jpg', content_type: 'image/jpeg') }
  end

  before do
    allow(Broadcaster).to receive(:ticket)
    allow(Broadcaster).to receive(:board)
    ActiveJob::Base.queue_adapter = :test
    Current.workspace = workspace
  end

  after { Current.reset }

  def old_post(status)
    Post.create!(workspace: workspace, ticket: ticket, social_account: account,
                 status: status, scheduled_at: 2.days.from_now)
  end

  it 'cancels prior scheduled/failed posts but PRESERVES unpublished history' do
    stale = old_post(:scheduled)
    failed = old_post(:failed)
    unpublished = old_post(:unpublished)

    described_class.call(ticket: ticket, user: user, creative_ids: [creative.id], mode: 'scheduled',
                         scheduled_at: 3.days.from_now.iso8601)

    expect(Post.exists?(stale.id)).to be(false)
    expect(Post.exists?(failed.id)).to be(false)
    expect(Post.exists?(unpublished.id)).to be(true) # history survives a re-publish
    expect(ticket.posts.status_scheduled.count).to eq(1) # the fresh bundle
  end

  it 'refuses to publish while a post is in flight (publishing)' do
    old_post(:publishing)

    expect do
      described_class.call(ticket: ticket, user: user, creative_ids: [creative.id], mode: 'immediate')
    end.to raise_error(Operations::Errors::Invalid, /em andamento/)
  end
end
