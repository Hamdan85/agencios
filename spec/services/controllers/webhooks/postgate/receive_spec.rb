# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Controllers::Webhooks::Postgate::Receive do
  let(:secret) { 'whsec_test' }
  let(:user) { User.create!(email: "pgwebhook-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'PG') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client_record) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client_record, name: 'Camp', color: '#7C3AED') }
  let(:ticket) do
    Operations::Tickets::Create.call(
      workspace: workspace, user: user, params: { project_id: project.id, title: 'T', channels: %w[pinterest] }
    )
  end
  let(:account) do
    client_record.social_accounts.create!(
      workspace: workspace, provider: 'pinterest', connection_source: :postgate,
      postgate_profile_id: 'prof_1', status: :connected
    )
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    allow(Vendors::Postgate::Webhook).to receive(:secret).and_return(secret)
    Current.workspace = workspace
    allow(Broadcaster).to receive(:ticket)
    allow(Broadcaster).to receive(:portal)
    allow(Operations::Push::Notify).to receive(:call)
  end

  after { Current.reset }

  def signed_header(payload, ts: Time.current.to_i.to_s)
    hmac = OpenSSL::HMAC.hexdigest('SHA256', secret, "#{ts}.#{payload}")
    "t=#{ts},v1=#{hmac}"
  end

  def build_post(status: :publishing, postgate_post_id: 'pg_1')
    Post.create!(
      workspace: workspace, ticket: ticket, social_account: account,
      status: status, scheduled_at: 1.hour.ago, caption: 'oi', postgate_post_id: postgate_post_id
    )
  end

  it 'returns :unauthorized for a bad signature' do
    payload = { id: 'evt_1', type: 'post.published', data: {} }.to_json

    status = described_class.call(signature: 't=123,v1=deadbeef', payload: payload)

    expect(status).to eq(:unauthorized)
  end

  it 'returns :unauthorized for a stale timestamp (> 5 minutes skew)' do
    payload = { id: 'evt_1', type: 'post.published', data: {} }.to_json
    stale_ts = 10.minutes.ago.to_i.to_s

    status = described_class.call(signature: signed_header(payload, ts: stale_ts), payload: payload)

    expect(status).to eq(:unauthorized)
  end

  it 'raises loudly when no webhook secret is configured (misconfiguration, not a bad request)' do
    allow(Vendors::Postgate::Webhook).to receive(:secret).and_return(nil)
    payload = { id: 'evt_1', type: 'post.published', data: {} }.to_json

    expect do
      described_class.call(signature: signed_header(payload), payload: payload)
    end.to raise_error(Vendors::Base::NotConfiguredError)
  end

  describe 'post.published' do
    it 'marks the post published using the single target' do
      post = build_post
      payload = {
        id: 'evt_1', type: 'post.published',
        data: { 'post_id' => 'pg_1',
                'targets' => [{ 'status' => 'published', 'platform_post_id' => 'ext-1', 'permalink' => 'https://x.test/1' }] }
      }.to_json

      status = described_class.call(signature: signed_header(payload), payload: payload)

      expect(status).to eq(:ok)
      post.reload
      expect(post).to be_status_published
      expect(post.external_post_id).to eq('ext-1')
      expect(post.permalink).to eq('https://x.test/1')
    end

    it 'is idempotent when the post was already published' do
      post = build_post(status: :published)
      post.update!(external_post_id: 'already-there')
      payload = {
        id: 'evt_1', type: 'post.published',
        data: { 'post_id' => 'pg_1', 'targets' => [{ 'status' => 'published', 'platform_post_id' => 'ext-2' }] }
      }.to_json

      described_class.call(signature: signed_header(payload), payload: payload)

      expect(post.reload.external_post_id).to eq('already-there')
    end

    it 'supports a nested post payload shape' do
      post = build_post
      payload = {
        id: 'evt_1', type: 'post.published',
        data: { 'post' => { 'id' => 'pg_1',
                             'targets' => [{ 'status' => 'published', 'platform_post_id' => 'ext-3' }] } }
      }.to_json

      described_class.call(signature: signed_header(payload), payload: payload)

      expect(post.reload).to be_status_published
      expect(post.external_post_id).to eq('ext-3')
    end
  end

  describe 'post.failed / post.partial' do
    it 'marks the post failed with the target error_message' do
      post = build_post
      payload = {
        id: 'evt_1', type: 'post.failed',
        data: { 'post_id' => 'pg_1', 'targets' => [{ 'status' => 'failed', 'error_message' => 'account disconnected' }] }
      }.to_json

      described_class.call(signature: signed_header(payload), payload: payload)

      post.reload
      expect(post).to be_status_failed
      expect(post.failure_reason).to eq('account disconnected')
    end

    it 'falls back to the i18n default reason when nothing more specific is given' do
      post = build_post
      payload = { id: 'evt_1', type: 'post.partial', data: { 'post_id' => 'pg_1', 'targets' => [{ 'status' => 'failed' }] } }.to_json

      described_class.call(signature: signed_header(payload), payload: payload)

      expect(post.reload.failure_reason).to eq(I18n.t('operations.posts.postgate_webhook_failed'))
    end

    it 'ignores a post that is not in publishing status' do
      post = build_post(status: :scheduled)
      payload = {
        id: 'evt_1', type: 'post.failed',
        data: { 'post_id' => 'pg_1', 'targets' => [{ 'status' => 'failed', 'error_message' => 'x' }] }
      }.to_json

      described_class.call(signature: signed_header(payload), payload: payload)

      expect(post.reload).to be_status_scheduled
    end
  end

  describe 'post.insights' do
    it 'records a PostMetric for the published post' do
      post = build_post(status: :published)
      payload = {
        id: 'evt_1', type: 'post.insights',
        data: { 'post_id' => 'pg_1',
                'targets' => [{ 'target_id' => 't1', 'platform' => 'pinterest', 'platform_post_id' => 'ext-1',
                                'metrics' => { 'impressions' => 100, 'reach' => 90, 'likes' => 5, 'comments' => 2,
                                               'shares' => 1, 'saved' => 3 } }] }
      }.to_json

      expect { described_class.call(signature: signed_header(payload), payload: payload) }
        .to change { post.post_metrics.count }.by(1)

      metric = post.post_metrics.last
      expect(metric.views).to eq(100)
      expect(metric.reach).to eq(90)
      expect(metric.likes).to eq(5)
      expect(metric.comments).to eq(2)
      expect(metric.shares).to eq(1)
      expect(metric.saves).to eq(3)
    end

    it 'skips a post that has not published yet' do
      post = build_post(status: :publishing)
      payload = {
        id: 'evt_1', type: 'post.insights',
        data: { 'post_id' => 'pg_1', 'targets' => [{ 'metrics' => { 'impressions' => 10 } }] }
      }.to_json

      expect { described_class.call(signature: signed_header(payload), payload: payload) }
        .not_to(change { post.post_metrics.count })
    end

    it 'skips silently when no matching post exists' do
      payload = {
        id: 'evt_1', type: 'post.insights',
        data: { 'post_id' => 'unknown', 'targets' => [{ 'metrics' => { 'impressions' => 10 } }] }
      }.to_json

      status = described_class.call(signature: signed_header(payload), payload: payload)

      expect(status).to eq(:ok)
    end
  end

  describe 'profile.reauth_required / profile.expired' do
    it 'flags the account needs_reauth' do
      account
      payload = { id: 'evt_1', type: 'profile.reauth_required', data: { 'profile_id' => 'prof_1', 'reason' => 'token_expired' } }.to_json

      described_class.call(signature: signed_header(payload), payload: payload)

      expect(account.reload).to be_status_needs_reauth
    end

    it 'flags the account on profile.expired too' do
      account
      payload = { id: 'evt_1', type: 'profile.expired', data: { 'profile_id' => 'prof_1', 'reason' => 'revoked' } }.to_json

      described_class.call(signature: signed_header(payload), payload: payload)

      expect(account.reload).to be_status_needs_reauth
    end
  end

  describe 'profile.disconnected' do
    it 'soft-revokes the account without calling the remote delete_profile' do
      account
      pg_client = instance_double(Vendors::Postgate::Client)
      allow(Vendors::Postgate::Client).to receive(:new).and_return(pg_client)
      allow(pg_client).to receive(:delete_profile)
      payload = { id: 'evt_1', type: 'profile.disconnected', data: { 'profile_id' => 'prof_1' } }.to_json

      described_class.call(signature: signed_header(payload), payload: payload)

      expect(account.reload).to be_status_revoked
      expect(pg_client).not_to have_received(:delete_profile)
    end
  end

  describe 'profile.stats_updated' do
    it 'reuses Operations::Social::SyncAccountInsights rather than writing AccountMetric directly' do
      account
      expect(Operations::Social::SyncAccountInsights).to receive(:call).with(social_account: account)
      payload = {
        id: 'evt_1', type: 'profile.stats_updated',
        data: { 'profile_id' => 'prof_1', 'platform' => 'pinterest', 'followers' => 500 }
      }.to_json

      described_class.call(signature: signed_header(payload), payload: payload)
    end
  end

  describe 'ignorable events' do
    it 'acknowledges profile.connected without side effects' do
      payload = { id: 'evt_1', type: 'profile.connected', data: {} }.to_json

      expect(described_class.call(signature: signed_header(payload), payload: payload)).to eq(:ok)
    end

    it 'acknowledges an unknown event type' do
      payload = { id: 'evt_1', type: 'something.new', data: {} }.to_json

      expect(described_class.call(signature: signed_header(payload), payload: payload)).to eq(:ok)
    end
  end

  it 'rescues a per-event handler failure and still returns :ok' do
    post = build_post
    allow(Operations::Posts::MarkPublished).to receive(:call).and_raise(StandardError, 'boom')
    payload = {
      id: 'evt_1', type: 'post.published',
      data: { 'post_id' => 'pg_1', 'targets' => [{ 'status' => 'published', 'platform_post_id' => 'ext-1' }] }
    }.to_json

    status = described_class.call(signature: signed_header(payload), payload: payload)

    expect(status).to eq(:ok)
    expect(post.reload).to be_status_publishing
  end
end
