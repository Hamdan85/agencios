# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Posts::MarkPublished do
  let(:user) { User.create!(email: "mp-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'MP') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) do
    Operations::Tickets::Create.call(
      workspace: workspace, user: user, params: { project_id: project.id, title: 'T', channels: %w[instagram] }
    )
  end
  let(:account) { client.social_accounts.create!(workspace: workspace, provider: 'instagram') }
  let(:post) do
    Post.create!(workspace: workspace, ticket: ticket, social_account: account,
                 status: :publishing, scheduled_at: 1.hour.ago)
  end

  before do
    Current.workspace = workspace
    allow(Broadcaster).to receive(:ticket)
    allow(Operations::Push::Notify).to receive(:call)
  end

  after { Current.reset }

  it 'publishes the post and stamps the external id + permalink given' do
    described_class.call(post: post, external_post_id: 'ext-1', permalink: 'https://x.test/p/1')

    post.reload
    expect(post).to be_status_published
    expect(post.external_post_id).to eq('ext-1')
    expect(post.permalink).to eq('https://x.test/p/1')
    expect(post.published_at).to be_present
    expect(Broadcaster).to have_received(:ticket).with(ticket, 'post_published', post_id: post.id, permalink: post.permalink)
    expect(Operations::Push::Notify).to have_received(:call).with(hash_including(title_key: 'push.post.published.title'))
  end

  it 'is nil-safe: omitting external_post_id/permalink keeps whatever the post already carries' do
    post.update!(external_post_id: 'kept-id', permalink: 'https://kept.test')

    described_class.call(post: post)

    post.reload
    expect(post.external_post_id).to eq('kept-id')
    expect(post.permalink).to eq('https://kept.test')
    expect(post).to be_status_published
  end

  it 'is idempotent — a second call on an already-published post is a no-op' do
    described_class.call(post: post, external_post_id: 'ext-1', permalink: 'https://x.test/p/1')
    published_at = post.reload.published_at

    described_class.call(post: post, external_post_id: 'ext-2', permalink: 'https://x.test/p/2')

    post.reload
    expect(post.published_at).to eq(published_at)
    expect(post.external_post_id).to eq('ext-1')
    expect(Broadcaster).to have_received(:ticket).with(ticket, 'post_published', anything).once
  end

  it 'advances the ticket to published once every post is live' do
    Operations::Tickets::ChangeStatus.call(ticket, 'scheduled', user: nil, force: true)

    described_class.call(post: post, external_post_id: 'ext-1', permalink: 'https://x.test/p/1')

    expect(ticket.reload.status).to eq('published')
  end
end
