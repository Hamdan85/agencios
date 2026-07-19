# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Posts::SyncMetrics do
  let(:user) { User.create!(email: "sm-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'Sm') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Metrics Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) { Operations::Tickets::Create.call(workspace: workspace, user: user, params: { project_id: project.id, title: 'T' }) }
  let(:account) do
    client.social_accounts.create!(workspace: workspace, provider: 'facebook',
                                  connection_type: 'facebook_login', page_access_token: 'tok')
  end
  let(:post) do
    Post.create!(workspace: workspace, ticket: ticket, social_account: account, status: :published,
                 scheduled_at: 1.day.ago, published_at: 1.day.ago, caption: 'oi',
                 external_post_id: 'ext_1')
  end

  before do
    Current.workspace = workspace
    Current.actor = user
    allow(Broadcaster).to receive(:ticket)
    allow(Broadcaster).to receive(:portal)
  end

  after { Current.reset }

  it 'stores the numbers the network returned' do
    allow(Publishers::SocialPublisher).to receive(:sync).and_return(
      { reach: 700, views: 900, likes: 12, comments: 3, shares: 5, saves: 0, raw: { 'ok' => true } }
    )

    expect { described_class.call(post: post) }.to change { post.post_metrics.count }.by(1)
    expect(post.post_metrics.last).to have_attributes(reach: 700, views: 900, likes: 12, comments: 3, shares: 5)
  end

  it 'writes NOTHING when the network could not be read — an all-zero row is a hole, not a zero' do
    allow(Publishers::SocialPublisher).to receive(:sync).and_return(nil)

    expect { described_class.call(post: post) }.not_to(change { post.post_metrics.count })
  end

  it 'flags the account for reconnection when the token is finished, then re-raises' do
    allow(Publishers::SocialPublisher).to receive(:sync)
      .and_raise(Vendors::Base::AuthenticationError.new('Invalid OAuth access token'))

    expect { described_class.call(post: post) }.to raise_error(Vendors::Base::AuthenticationError)
    expect(account.reload).to be_status_needs_reauth
    expect(post.post_metrics.count).to eq(0)
  end

  it 'leaves a genuine zero-performing post recorded as zero' do
    allow(Publishers::SocialPublisher).to receive(:sync).and_return(
      { reach: 0, views: 0, likes: 0, comments: 0, shares: 0, saves: 0, raw: { 'data' => [] } }
    )

    expect { described_class.call(post: post) }.to change { post.post_metrics.count }.by(1)
  end
end
