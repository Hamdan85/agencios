# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Posts::PollPostgateStatusJob do
  let(:user) { User.create!(email: "pgpoll-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'PG') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client_record) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client_record, name: 'Camp', color: '#7C3AED') }
  let(:ticket) do
    Operations::Tickets::Create.call(
      workspace: workspace, user: user, params: { project_id: project.id, title: 'T', channels: %w[pinterest] }
    )
  end
  let(:account) do
    client_record.social_accounts.create!(workspace: workspace, provider: 'pinterest',
                                          connection_source: :postgate, postgate_profile_id: 'prof_1')
  end
  let(:pg_client) { instance_double(Vendors::Postgate::Client) }

  before do
    ActiveJob::Base.queue_adapter = :test
    Current.workspace = workspace
    allow(Vendors::Postgate::Client).to receive(:new).and_return(pg_client)
    allow(Broadcaster).to receive(:ticket)
    allow(Operations::Push::Notify).to receive(:call)
  end

  after { Current.reset }

  def build_post
    Post.create!(workspace: workspace, ticket: ticket, social_account: account,
                 status: :publishing, scheduled_at: 1.hour.ago, caption: 'oi', postgate_post_id: 'pg_1')
  end

  it 'marks the post published when the target reports published' do
    post = build_post
    allow(pg_client).to receive(:get_post).with('pg_1').and_return(
      { 'id' => 'pg_1', 'status' => 'published',
        'targets' => [{ 'status' => 'published', 'platform_post_id' => 'ext-1', 'permalink' => 'https://x.test/1' }] }
    )

    described_class.perform_now(post.id, 3)

    post.reload
    expect(post).to be_status_published
    expect(post.external_post_id).to eq('ext-1')
    expect(post.permalink).to eq('https://x.test/1')
  end

  it 'marks the post failed when the target reports failed, carrying the error message' do
    post = build_post
    allow(pg_client).to receive(:get_post).with('pg_1').and_return(
      { 'id' => 'pg_1', 'status' => 'partial',
        'targets' => [{ 'status' => 'failed', 'error_message' => 'account disconnected' }] }
    )

    described_class.perform_now(post.id, 2)

    post.reload
    expect(post).to be_status_failed
    expect(post.failure_reason).to eq('account disconnected')
  end

  it 'marks the post failed when the whole PostGate post is canceled with no settled target' do
    post = build_post
    allow(pg_client).to receive(:get_post).with('pg_1').and_return(
      { 'id' => 'pg_1', 'status' => 'canceled', 'targets' => [{ 'status' => 'pending' }] }
    )

    described_class.perform_now(post.id, 1)

    expect(post.reload).to be_status_failed
  end

  it 'reschedules with a growing wait while the target is still in flight' do
    post = build_post
    allow(pg_client).to receive(:get_post).with('pg_1').and_return(
      { 'id' => 'pg_1', 'status' => 'processing', 'targets' => [{ 'status' => 'publishing' }] }
    )

    expect { described_class.perform_now(post.id, 2) }
      .to have_enqueued_job(described_class).with(post.id, 3).at(a_value_within(2.seconds).of(1.minute.from_now))

    expect(post.reload).to be_status_publishing
  end

  it 'reschedules (not fails) on a transient vendor error while polling' do
    post = build_post
    allow(pg_client).to receive(:get_post).with('pg_1').and_raise(Vendors::Base::ServerError.new('timeout'))

    expect { described_class.perform_now(post.id, 1) }
      .to have_enqueued_job(described_class).with(post.id, 2)

    expect(post.reload).to be_status_publishing
  end

  it 'gives up with an i18n timeout reason once the ~2h budget is exhausted' do
    post = build_post
    allow(pg_client).to receive(:get_post).with('pg_1').and_return(
      { 'id' => 'pg_1', 'status' => 'processing', 'targets' => [{ 'status' => 'publishing' }] }
    )

    described_class.perform_now(post.id, 20)

    post.reload
    expect(post).to be_status_failed
    expect(post.failure_reason).to eq(I18n.t('operations.posts.postgate_poll_timeout'))
  end

  it 'is idempotent — a no-op when the post was already finalized (e.g. by a webhook)' do
    post = build_post
    post.update!(status: :published, external_post_id: 'already-there')
    allow(pg_client).to receive(:get_post)

    described_class.perform_now(post.id, 2)

    expect(pg_client).not_to have_received(:get_post)
    expect(post.reload.external_post_id).to eq('already-there')
  end
end
