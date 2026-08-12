# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Posts::Publish do
  let(:user) { User.create!(email: "pub-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'Pub') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) do
    Operations::Tickets::Create.call(
      workspace: workspace, user: user, params: { project_id: project.id, title: 'T', channels: %w[instagram] }
    )
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    Current.workspace = workspace
    allow(Broadcaster).to receive(:ticket)
    allow(Operations::Push::Notify).to receive(:call)
  end

  after { Current.reset }

  def build_post(account)
    Post.create!(workspace: workspace, ticket: ticket, social_account: account,
                 status: :scheduled, scheduled_at: 1.hour.ago, caption: 'oi')
  end

  context 'a direct-vendor account' do
    let(:account) { client.social_accounts.create!(workspace: workspace, provider: 'instagram') }

    it 'publishes synchronously, unchanged: status, external id, permalink, notifications' do
      post = build_post(account)
      allow(Publishers::SocialPublisher).to receive(:publish)
        .and_return(external_post_id: 'ext-1', permalink: 'https://instagram.test/p/1')

      described_class.call(post: post)

      post.reload
      expect(post).to be_status_published
      expect(post.external_post_id).to eq('ext-1')
      expect(post.permalink).to eq('https://instagram.test/p/1')
      expect(post.postgate_post_id).to be_nil
      expect(Operations::Push::Notify).to have_received(:call).with(hash_including(title_key: 'push.post.published.title'))
      expect(Broadcaster).to have_received(:ticket).with(ticket, 'post_published', post_id: post.id, permalink: post.permalink)
    end
  end

  context 'a postgate-sourced account whose target published within the publish poll window' do
    let(:account) do
      client.social_accounts.create!(workspace: workspace, provider: 'pinterest',
                                     connection_source: :postgate, postgate_profile_id: 'prof_1')
    end

    it 'marks published AND keeps the postgate post id for later metric syncs / unpublish' do
      post = build_post(account)
      allow(Publishers::SocialPublisher).to receive(:publish)
        .and_return(external_post_id: 'pin-9', permalink: 'https://pinterest.test/pin/9', postgate_post_id: 'pg_post_2')

      described_class.call(post: post)

      post.reload
      expect(post).to be_status_published
      expect(post.external_post_id).to eq('pin-9')
      expect(post.postgate_post_id).to eq('pg_post_2')
    end
  end

  context 'a postgate-sourced account whose target is still pending' do
    let(:account) do
      client.social_accounts.create!(workspace: workspace, provider: 'pinterest',
                                     connection_source: :postgate, postgate_profile_id: 'prof_1')
    end

    it 'leaves the post publishing, records the postgate id, and enqueues the poll job — no notifications yet' do
      post = build_post(account)
      allow(Publishers::SocialPublisher).to receive(:publish)
        .and_return(pending: true, postgate_post_id: 'pg_post_1')

      expect { described_class.call(post: post) }
        .to have_enqueued_job(Posts::PollPostgateStatusJob).with(post.id, 1)

      post.reload
      expect(post).to be_status_publishing
      expect(post.postgate_post_id).to eq('pg_post_1')
      expect(post.external_post_id).to be_nil
      expect(Operations::Push::Notify).not_to have_received(:call).with(hash_including(title_key: 'push.post.published.title'))
    end
  end
end
